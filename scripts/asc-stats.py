#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]>=2.8", "requests>=2.31"]
# ///
"""Query App Store Connect for JobHunt's builds, versions, reviews and sales.

Auth uses an App Store Connect API key (Users and Access -> Integrations). The private key is
read from ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 and never printed.

    scripts/asc-stats.py builds          # recent uploads + processing state
    scripts/asc-stats.py versions        # App Store version records and their state
    scripts/asc-stats.py reviews         # latest customer reviews
    scripts/asc-stats.py sales --days 30 # daily units (needs vendor_number)

Config lives in ~/.appstoreconnect/config.json:

    {"issuer_id": "...", "key_id": "68BGNV3CCC", "app_id": "6782679255", "vendor_number": "..."}

issuer_id and key_id are on the same Integrations page as the key. vendor_number is only needed
for `sales`, and is in App Store Connect -> Payments and Financial Reports (top-left, under the
legal entity name). Neither is secret, but the .p8 is: keep it 600 and out of git.
"""

import argparse
import csv
import datetime as dt
import gzip
import io
import json
import pathlib
import sys
import time

import jwt
import requests

HOME = pathlib.Path.home()
CONFIG = HOME / ".appstoreconnect" / "config.json"
KEY_DIR = HOME / ".appstoreconnect" / "private_keys"
API = "https://api.appstoreconnect.apple.com"


def load_config() -> dict:
    if not CONFIG.exists():
        sys.exit(
            f"No {CONFIG}.\nCreate it with at least issuer_id and key_id — see the module docstring."
        )
    cfg = json.loads(CONFIG.read_text())
    for required in ("issuer_id", "key_id"):
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


def get(cfg: dict, path: str, **params) -> requests.Response:
    r = requests.get(
        f"{API}{path}",
        headers={"Authorization": f"Bearer {token(cfg)}"},
        params=params,
        timeout=60,
    )
    if r.status_code >= 400:
        # Apple's errors are specific and worth showing verbatim; they name the bad parameter.
        sys.exit(f"HTTP {r.status_code} on {path}\n{r.text[:2000]}")
    return r


def cmd_builds(cfg: dict, args) -> None:
    data = get(
        cfg,
        "/v1/builds",
        **{
            "filter[app]": cfg["app_id"],
            "limit": args.limit,
            "sort": "-uploadedDate",
            "fields[builds]": "version,uploadedDate,processingState,expired",
        },
    ).json()["data"]
    print(f"{'build':<14}{'uploaded':<22}{'state':<14}expired")
    for b in data:
        a = b["attributes"]
        print(
            f"{a['version']:<14}{a['uploadedDate']:<22}{a['processingState']:<14}{a['expired']}"
        )


def cmd_versions(cfg: dict, args) -> None:
    data = get(
        cfg,
        f"/v1/apps/{cfg['app_id']}/appStoreVersions",
        limit=args.limit,
        **{"fields[appStoreVersions]": "versionString,appStoreState,createdDate,releaseType"},
    ).json()["data"]
    print(f"{'version':<12}{'state':<28}created")
    for v in data:
        a = v["attributes"]
        print(f"{a['versionString']:<12}{a.get('appStoreState', '?'):<28}{a.get('createdDate', '')}")


def cmd_reviews(cfg: dict, args) -> None:
    data = get(
        cfg,
        f"/v1/apps/{cfg['app_id']}/customerReviews",
        limit=args.limit,
        sort="-createdDate",
    ).json()["data"]
    if not data:
        print("No reviews yet.")
        return
    for r in data:
        a = r["attributes"]
        print(f"{'*' * a['rating']:<6} {a['createdDate'][:10]}  {a.get('territory', '')}")
        if a.get("title"):
            print(f"  {a['title']}")
        if a.get("body"):
            print(f"  {a['body'].strip()}")
        print()


def cmd_sales(cfg: dict, args) -> None:
    """Daily units from Sales and Trends. Reports appear ~24h late and are absent on zero-sales days."""
    if not cfg.get("vendor_number"):
        sys.exit(f"`sales` needs vendor_number in {CONFIG} — see the module docstring.")
    totals: dict[str, int] = {}
    for offset in range(1, args.days + 1):
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
        # 404 is the normal answer for a day with no sales, or one Apple hasn't published yet.
        if r.status_code == 404:
            continue
        if r.status_code >= 400:
            sys.exit(f"HTTP {r.status_code} for {day}\n{r.text[:2000]}")
        text = gzip.decompress(r.content).decode("utf-8")
        for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
            if row.get("Apple Identifier") == str(cfg["app_id"]):
                totals[day] = totals.get(day, 0) + int(row["Units"])

    if not totals:
        print(f"No sales rows in the last {args.days} days (or Apple hasn't published them yet).")
        return
    for day in sorted(totals):
        print(f"{day}  {totals[day]:>5}")
    print(f"{'total':<12}{sum(totals.values()):>5}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (
        ("builds", cmd_builds),
        ("versions", cmd_versions),
        ("reviews", cmd_reviews),
    ):
        s = sub.add_parser(name)
        s.add_argument("--limit", type=int, default=10)
        s.set_defaults(fn=fn)
    s = sub.add_parser("sales")
    s.add_argument("--days", type=int, default=30)
    s.set_defaults(fn=cmd_sales)

    args = p.parse_args()
    cfg = load_config()
    if args.cmd != "sales" and not cfg.get("app_id"):
        sys.exit(f"{CONFIG} is missing 'app_id' (JobHunt is 6782679255).")
    args.fn(cfg, args)


if __name__ == "__main__":
    main()
