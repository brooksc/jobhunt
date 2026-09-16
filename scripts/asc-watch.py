#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]>=2.8", "requests>=2.31"]
# ///
"""Report new App Store downloads or reviews for JobHunt — and stay silent when there are none.

Meant to run once a day from launchd (see scripts/com.brooksc.jobhunt.asc-watch.plist). Exits 0
saying nothing when nothing has changed, so a notification means something actually happened.

    scripts/asc-watch.py               # check, notify if there is news
    scripts/asc-watch.py --dry-run     # print what it would report, touch no state
    scripts/asc-watch.py --reset       # forget history and re-baseline on the next run
    scripts/asc-watch.py --force       # report current numbers even if unchanged (a smoke test)

Auth and config are shared with asc-stats.py: ~/.appstoreconnect/config.json plus the .p8 in
~/.appstoreconnect/private_keys/. The private key is never printed.

WHY THERE IS STATE. Apple publishes a day's sales report roughly 24 hours late, and a zero-sales day
simply 404s rather than returning zero. So "new downloads since yesterday" cannot be answered by
looking at yesterday alone — a day can appear two days after the fact. This tracks which report DATES
have already been reported and looks back over a window, so a late-published day is reported once,
when it shows up, and never twice.

FIRST RUN IS SILENT ON PURPOSE. With no state there is no such thing as "new", and reporting the
whole lookback window as news would train you to ignore the notification on day one. The first run
records where things stand and says nothing.
"""

import argparse
import csv
import datetime as dt
import gzip
import io
import json
import pathlib
import subprocess
import sys
import time

import jwt
import requests

HOME = pathlib.Path.home()
CONFIG = HOME / ".appstoreconnect" / "config.json"
KEY_DIR = HOME / ".appstoreconnect" / "private_keys"
STATE = HOME / ".appstoreconnect" / "jobhunt-watch-state.json"
API = "https://api.appstoreconnect.apple.com"

# Apple publishes late, so look further back than a day. Any date in this window that has not been
# reported before counts as news. 7 gives a late report several chances to be noticed.
LOOKBACK_DAYS = 7


def load_config() -> dict:
    if not CONFIG.exists():
        sys.exit(f"No {CONFIG}. See scripts/asc-stats.py for the shape.")
    cfg = json.loads(CONFIG.read_text())
    for required in ("issuer_id", "key_id", "app_id"):
        if not cfg.get(required):
            sys.exit(f"{CONFIG} is missing {required!r}.")
    return cfg


def token(cfg: dict) -> str:
    """A 20-minute ES256 JWT. Apple rejects anything longer."""
    key_path = KEY_DIR / f"AuthKey_{cfg['key_id']}.p8"
    if not key_path.exists():
        sys.exit(f"No private key at {key_path}.")
    now = int(time.time())
    return jwt.encode(
        {"iss": cfg["issuer_id"], "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": cfg["key_id"], "typ": "JWT"},
    )


def load_state() -> dict:
    if not STATE.exists():
        return {}
    try:
        return json.loads(STATE.read_text())
    except json.JSONDecodeError:
        # A truncated state file must not wedge the watcher forever. Re-baseline instead, and say so.
        print(f"warning: {STATE} was unreadable; re-baselining", file=sys.stderr)
        return {}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def fetch_reviews(cfg: dict, limit: int = 20) -> list[dict]:
    r = requests.get(
        f"{API}/v1/apps/{cfg['app_id']}/customerReviews",
        headers={"Authorization": f"Bearer {token(cfg)}"},
        params={"limit": limit, "sort": "-createdDate"},
        timeout=60,
    )
    if r.status_code == 403:
        sys.exit("403 reading reviews — the API key's role does not allow it.")
    r.raise_for_status()
    return r.json()["data"]


def fetch_daily_units(cfg: dict, days: int) -> dict[str, int]:
    """{date: units} for the last `days` days. Absent days are genuinely absent, not zero."""
    if not cfg.get("vendor_number"):
        sys.exit(f"Downloads need vendor_number in {CONFIG}.")
    totals: dict[str, int] = {}
    for offset in range(1, days + 1):
        day = (dt.date.today() - dt.timedelta(days=offset)).isoformat()
        r = requests.get(
            f"{API}/v1/salesReports",
            headers={"Authorization": f"Bearer {token(cfg)}"},
            params={
                "filter[frequency]": "DAILY",
                "filter[reportType]": "SALES",
                "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": cfg["vendor_number"],
                "filter[reportDate]": day,
            },
            timeout=60,
        )
        # 404 is the normal answer for a zero-sales day, or one Apple hasn't published yet.
        if r.status_code == 404:
            continue
        if r.status_code == 403:
            sys.exit(
                "403 reading Sales and Trends — the key needs Admin, Finance or Sales access. A "
                "key's role is fixed at creation, so this needs a new key, not a permission edit."
            )
        r.raise_for_status()
        text = gzip.decompress(r.content).decode("utf-8")
        for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
            if row.get("Apple Identifier") == str(cfg["app_id"]):
                totals[day] = totals.get(day, 0) + int(row["Units"])
    return totals


def notify(title: str, message: str) -> None:
    """macOS notification, best-effort. A failure here must not lose the report — it is also on stdout."""
    try:
        subprocess.run(
            ["terminal-notifier", "-title", title, "-message", message, "-group", "jobhunt-asc"],
            check=False,
            capture_output=True,
            timeout=15,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        pass


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help="report but do not record state")
    ap.add_argument("--reset", action="store_true", help="forget history, re-baseline next run")
    ap.add_argument("--force", action="store_true", help="report even when nothing is new")
    ap.add_argument("--days", type=int, default=LOOKBACK_DAYS)
    args = ap.parse_args()

    if args.reset:
        STATE.unlink(missing_ok=True)
        print(f"State cleared. The next run will re-baseline silently.")
        return

    cfg = load_config()
    state = load_state()
    first_run = not state

    units = fetch_daily_units(cfg, args.days)
    reviews = fetch_reviews(cfg)

    seen_days = set(state.get("reported_days", []))
    seen_reviews = set(state.get("reported_review_ids", []))

    new_days = {d: n for d, n in units.items() if d not in seen_days and n > 0}
    new_reviews = [r for r in reviews if r["id"] not in seen_reviews]

    next_state = {
        # Keep the window bounded: only dates that can still be inside a future lookback matter.
        "reported_days": sorted(seen_days | set(units))[-90:],
        "reported_review_ids": sorted(seen_reviews | {r["id"] for r in reviews})[-200:],
        "last_checked": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    }

    if first_run and not args.force:
        if not args.dry_run:
            save_state(next_state)
        print(
            f"Baselined: {sum(units.values())} download(s) across {len(units)} day(s) and "
            f"{len(reviews)} review(s) already on record. Future runs report only what is new."
        )
        return

    if not new_days and not new_reviews and not args.force:
        if not args.dry_run:
            save_state(next_state)
        return  # Silence is the point.

    lines: list[str] = []
    if new_days:
        total = sum(new_days.values())
        detail = ", ".join(f"{d} ({n})" for d, n in sorted(new_days.items()))
        lines.append(f"{total} new download{'s' if total != 1 else ''} — {detail}")
    if new_reviews:
        lines.append(f"{len(new_reviews)} new review{'s' if len(new_reviews) != 1 else ''}:")
        for r in new_reviews:
            a = r["attributes"]
            stars = "*" * int(a.get("rating", 0))
            lines.append(f"  {stars:<5} {a.get('territory', '')} {a.get('title', '') or ''}".rstrip())
            if a.get("body"):
                body = " ".join(a["body"].split())
                lines.append(f"        {body[:200]}")
    if args.force and not lines:
        lines.append(
            f"Nothing new. {sum(units.values())} download(s) in the last {args.days} days, "
            f"{len(reviews)} review(s) total."
        )

    report = "\n".join(lines)
    print(report)

    # A notification is a side effect, so --dry-run suppresses it too. Printing to stdout is how you
    # inspect the report without putting a banner on someone's screen.
    if not args.dry_run:
        notify("JobHunt — App Store", report[:400])
        save_state(next_state)


if __name__ == "__main__":
    main()
