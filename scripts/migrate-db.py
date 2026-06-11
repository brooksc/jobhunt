#!/usr/bin/env python3
"""
Migrate data from the old Electron app's SQLite database (jobhunt.db)
into the new Swift app's SwiftData store (jobhunt.store).

Usage: python3 scripts/migrate-db.py [--dry-run]
"""

import sys
import sqlite3
import shutil
import os
from datetime import datetime, timezone

DRY_RUN = "--dry-run" in sys.argv

OLD_DB = os.path.expanduser("~/Library/Application Support/Jobhunt/jobhunt.db")
NEW_STORE = os.path.expanduser("~/Library/Application Support/Jobhunt/jobhunt.store")
BACKUP = NEW_STORE + ".pre-migration-bak"

# CoreData epoch is 2001-01-01 00:00:00 UTC (vs Unix epoch 1970-01-01)
COREDATA_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def to_cd(iso_str):
    """Convert ISO 8601 string to CoreData timestamp (seconds since 2001-01-01 UTC)."""
    if not iso_str:
        return None
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return (dt - COREDATA_EPOCH).total_seconds()
    except Exception:
        return None


def check_preconditions():
    if not os.path.exists(OLD_DB):
        sys.exit(f"ERROR: old database not found at {OLD_DB}")
    if not os.path.exists(NEW_STORE):
        sys.exit(f"ERROR: new store not found at {NEW_STORE}")

    # Check that the Swift app is not running
    import subprocess
    result = subprocess.run(["pgrep", "-x", "Jobhunt"], capture_output=True)
    if result.returncode == 0:
        sys.exit("ERROR: Jobhunt app is running. Please quit it before migrating.")


def migrate():
    check_preconditions()

    print(f"Source: {OLD_DB}")
    print(f"Target: {NEW_STORE}")
    if DRY_RUN:
        print("DRY RUN — no changes will be written.\n")

    # Backup the store
    if not DRY_RUN:
        shutil.copy2(NEW_STORE, BACKUP)
        for ext in ("-shm", "-wal"):
            src = NEW_STORE + ext
            if os.path.exists(src):
                shutil.copy2(src, BACKUP + ext)
        print(f"Backed up store to {BACKUP}")

    old = sqlite3.connect(OLD_DB)
    old.row_factory = sqlite3.Row

    new = sqlite3.connect(NEW_STORE)
    new.row_factory = sqlite3.Row

    # Checkpoint any pending WAL writes into the main store file
    new.execute("PRAGMA wal_checkpoint(TRUNCATE)")

    # Load entity type numbers from Z_PRIMARYKEY
    ent = {}
    for row in new.execute("SELECT Z_NAME, Z_ENT FROM Z_PRIMARYKEY"):
        ent[row["Z_NAME"]] = row["Z_ENT"]
    print(f"Entity types: {dict(ent)}\n")

    # ------------------------------------------------------------------ counts
    old_counts = {
        t: old.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        for t in ("jobs", "captures", "sites", "resumes", "settings")
    }
    print("Old DB counts:")
    for k, v in old_counts.items():
        print(f"  {k}: {v}")
    print()

    if DRY_RUN:
        old.close()
        new.close()
        return

    # ------------------------------------------------------------------ clear existing data
    # Keep settings but clear jobs/captures/sites/resumes and related
    tables_to_clear = [
        "ZJOBACTION", "ZJOBFITSCORE", "ZJOBVENT",
        "ZLLMREQUESTATTEMPT", "ZLLMREQUEST",
        "ZDATAQUALITYREVIEW", "ZDUPLICATEDECISION",
        "ZJOBEVENT", "ZCOVERLETTER", "ZCONTACT",
        "ZSITEREVIEW", "ZSITE",
        "ZRESUME", "ZJOB", "ZCAPTURE",
    ]
    for tbl in tables_to_clear:
        try:
            new.execute(f"DELETE FROM {tbl}")
        except Exception:
            pass  # table may not exist in this schema version

    # ------------------------------------------------------------------ import resumes
    resume_pk_map = {}  # old string id -> new integer Z_PK
    pk = 1
    for r in old.execute("SELECT * FROM resumes ORDER BY sort_order, created_at"):
        resume_pk_map[r["id"]] = pk
        new.execute(
            "INSERT INTO ZRESUME (Z_PK, Z_ENT, Z_OPT, ZACTIVE, ZCHARCOUNT, ZSORTORDER,"
            " ZCREATEDAT, ZUPDATEDAT, ZFILENAME, ZID, ZNAME, ZTEXT) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (pk, ent["Resume"], 1,
             1 if r["active"] else 0,
             r["char_count"],
             r["sort_order"],
             to_cd(r["created_at"]), to_cd(r["updated_at"]),
             r["filename"], r["id"], r["name"], r["text"]),
        )
        pk += 1
    print(f"Imported {len(resume_pk_map)} resumes.")

    # ------------------------------------------------------------------ import sites
    site_pk_map = {}
    pk = 1
    for s in old.execute("SELECT * FROM sites ORDER BY created_at"):
        site_pk_map[s["id"]] = pk
        new.execute(
            "INSERT INTO ZSITE (Z_PK, Z_ENT, Z_OPT, ZINTERVALDAYS,"
            " ZADDEDAT, ZCREATEDAT, ZLASTREVIEWEDAT, ZNEXTREVIEWAT, ZUPDATEDAT,"
            " ZCOMPANYDESCRIPTION, ZCOMPANYNAME, ZCOMPANYWEBSITE, ZID, ZJOBSURL,"
            " ZNOTE, ZORIGIN, ZPAGETITLE, ZSTATE, ZURL) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (pk, ent["Site"], 1,
             s["interval_days"],
             to_cd(s["added_at"] or s["created_at"]),
             to_cd(s["created_at"]),
             to_cd(s["last_reviewed_at"]),
             to_cd(s["next_review_at"]),
             to_cd(s["updated_at"]),
             s["company_description"] or "",
             s["company_name"] or "",
             s["company_website"] or "",
             s["id"],
             s["jobs_url"] or "",
             s["note"] or "",
             s["origin"],
             s["page_title"] or "",
             s["state"] or "not_reviewed",
             s["url"]),
        )
        pk += 1
    print(f"Imported {len(site_pk_map)} sites.")

    # ------------------------------------------------------------------ import captures + jobs (paired)
    # Each capture has exactly one job; import them together keeping integer PKs aligned.
    capture_pk_map = {}
    job_pk_map = {}
    cap_pk = 1
    job_pk = 1

    jobs = {r["id"]: r for r in old.execute("SELECT * FROM jobs")}
    captures = {r["id"]: r for r in old.execute("SELECT * FROM captures")}

    # Build cap_id -> job mapping
    cap_to_job = {}
    for j in jobs.values():
        cap_to_job[j["capture_id"]] = j["id"]

    for cap_id, cap in sorted(captures.items(), key=lambda x: x[1]["created_at"]):
        job_id = cap_to_job.get(cap_id)
        if not job_id:
            continue  # orphan capture, skip
        j = jobs[job_id]

        capture_pk_map[cap_id] = cap_pk
        job_pk_map[job_id] = job_pk

        # Insert capture
        new.execute(
            "INSERT INTO ZCAPTURE (Z_PK, Z_ENT, Z_OPT, ZJOB,"
            " ZCAPTUREDAT, ZCREATEDAT,"
            " ZCANONICALURL, ZCLEANEDDESCRIPTION, ZCLEANEDHASH, ZID, ZPAGETITLE,"
            " ZRAWHASH, ZSELECTEDTEXT, ZSTRUCTUREDDATAJSON, ZURL, ZUSERNOTE, ZVISIBLETEXT)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (cap_pk, ent["Capture"], 1, job_pk,
             to_cd(cap["captured_at"]), to_cd(cap["created_at"]),
             cap["canonical_url"], cap["cleaned_description"], cap["cleaned_hash"],
             cap["id"], cap["page_title"], cap["raw_hash"],
             cap["selected_text"], cap["structured_data_json"],
             cap["url"], cap["user_note"], cap["visible_text"]),
        )

        # Status raw values match the old DB exactly (not_available, saved, applied, etc.)
        status = j["status"]

        # Insert job
        new.execute(
            "INSERT INTO ZJOB (Z_PK, Z_ENT, Z_OPT,"
            " ZFITSCORE, ZJOBNUMBER, ZRATING, ZSALARYMAX, ZSALARYMIN, ZUNREAD,"
            " ZCAPTURE, ZQUALITYREVIEW,"
            " ZCREATEDAT, ZDUPLICATECONFIDENCE, ZEXTRACTEDAT, ZEXTRACTIONCONFIDENCE,"
            " ZLASTOPENEDAT, ZUPDATEDAT,"
            " ZAPPLICATIONURL, ZCOMPANY, ZDUPLICATEOFJOBID, ZEMPLOYMENTTYPE,"
            " ZEXTRACTEDJSON, ZEXTRACTIONERROR, ZEXTRACTIONMODEL, ZEXTRACTIONSTATUS,"
            " ZFITSCOREJSON, ZFITSTATUS, ZID, ZLOCATION, ZMANUALOVERRIDESJSON,"
            " ZREMOTETYPE, ZSALARYCURRENCY, ZSALARYNOTE, ZSENIORITY, ZSTATUS, ZTITLE)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (job_pk, ent["Job"], 1,
             j["fit_score"], j["job_number"], j["rating"],
             j["salary_max"], j["salary_min"], j["unread"] or 0,
             cap_pk, None,  # ZCAPTURE FK, ZQUALITYREVIEW
             to_cd(j["created_at"]),
             j["duplicate_confidence"], to_cd(j["extracted_at"]),
             j["extraction_confidence"],
             to_cd(j["last_opened_at"]), to_cd(j["updated_at"]),
             j["application_url"], j["company"],
             j["duplicate_of_job_id"],  # string ID ref — OK for lookup display
             j["employment_type"],
             j["extracted_json"], j["extraction_error"], j["extraction_model"],
             j["extraction_status"] or "pending",
             j["fit_score_json"], j["fit_status"] or "none",
             j["id"], j["location"],
             j["manual_overrides"] or "[]",
             j["remote_type"], j["salary_currency"], j["salary_note"],
             j["seniority"], status, j["title"]),
        )

        cap_pk += 1
        job_pk += 1

    print(f"Imported {len(job_pk_map)} jobs (with captures).")

    # ------------------------------------------------------------------ import settings from old DB
    # Only import keys that don't already exist or where old value is meaningful
    keys_to_import = {
        "job_description_markdown",
        "site_review_interval_days",
        "followup_default_days",
    }
    existing_keys = {
        r[0] for r in new.execute("SELECT ZKEY FROM ZSETTING")
    }
    set_pk = new.execute("SELECT MAX(Z_PK) FROM ZSETTING").fetchone()[0] or 0
    for s in old.execute("SELECT key, value FROM settings"):
        if s["key"] not in keys_to_import:
            continue
        if s["key"] in existing_keys:
            # Update existing setting
            new.execute(
                "UPDATE ZSETTING SET ZVALUE=? WHERE ZKEY=?",
                (s["value"], s["key"])
            )
        else:
            set_pk += 1
            now_cd = (datetime.now(timezone.utc) - COREDATA_EPOCH).total_seconds()
            new.execute(
                "INSERT INTO ZSETTING (Z_PK, Z_ENT, Z_OPT, ZUPDATEDAT, ZKEY, ZVALUE)"
                " VALUES (?,?,?,?,?,?)",
                (set_pk, ent["Setting"], 1, now_cd, s["key"], s["value"]),
            )
    print("Imported settings (job_description_markdown, intervals).")

    # ------------------------------------------------------------------ update Z_PRIMARYKEY counters
    new.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Capture'", (cap_pk - 1,))
    new.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Job'", (job_pk - 1,))
    new.execute(
        "UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Resume'",
        (len(resume_pk_map),)
    )
    new.execute(
        "UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Site'",
        (len(site_pk_map),)
    )
    new.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Setting'", (set_pk,))

    new.commit()
    # Final checkpoint
    new.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    new.commit()
    new.close()
    old.close()

    print(f"\nMigration complete!")
    print(f"  Captures: {cap_pk - 1}")
    print(f"  Jobs:     {job_pk - 1}")
    print(f"  Sites:    {len(site_pk_map)}")
    print(f"  Resumes:  {len(resume_pk_map)}")
    print(f"\nBackup saved to: {BACKUP}")
    print("You can now launch the Jobhunt app.")


if __name__ == "__main__":
    migrate()
