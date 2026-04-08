#!/usr/bin/env python3
"""Check Xcode Cloud build status for WraithVPN.

Prerequisites:
  pip install pyjwt requests

Setup:
  Download your App Store Connect API key (.p8) from:
    App Store Connect → Users & Access → Integrations → App Store Connect API
  Then set these environment variables (or edit the constants below):
    ASC_KEY_ID      — Key ID shown in App Store Connect
    ASC_ISSUER_ID   — Issuer ID shown on the same page
    ASC_KEY_PATH    — Path to your downloaded .p8 file
"""
import jwt, time, requests, sys, os

KEY_ID     = os.environ.get("ASC_KEY_ID")
ISSUER_ID  = os.environ.get("ASC_ISSUER_ID")
KEY_PATH   = os.environ.get("ASC_KEY_PATH")
PRODUCT_ID = "044EC9AF-C09E-418D-A9DD-0D85E3F55EE1"

if not KEY_ID or not ISSUER_ID or not KEY_PATH:
    print("Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH environment variables.")
    print("Get these from App Store Connect → Users & Access → Integrations.")
    sys.exit(1)
WORKFLOWS  = {
    "9524E3E9-4C37-4492-B54A-FCC6FC287E5B": "Deploy",
    "F27DCAD5-F3FE-4D0E-B641-697BD7964F9C": "Default",
    "8C741733-3769-453A-8C0E-85BDEFDFC72E": "Untitled Workflow",
}

with open(KEY_PATH) as f:
    private_key = f.read()

payload = {"iss": ISSUER_ID, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
token = jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})
headers = {"Authorization": f"Bearer {token}"}

any_builds = False
for wf_id, wf_name in WORKFLOWS.items():
    r = requests.get(
        f"https://api.appstoreconnect.apple.com/v1/ciWorkflows/{wf_id}/buildRuns",
        params={"limit": 5},
        headers=headers,
    )
    if r.status_code == 404:
        print(f"{wf_name}: API error 404")
        continue
    data = r.json().get("data", [])
    if not data:
        continue
    any_builds = True
    print(f"\n── {wf_name} ──")
    for build in data:
        attrs = build["attributes"]
        progress   = attrs.get("executionProgress", "?")
        status     = attrs.get("completionStatus", "-")
        started_at = attrs.get("sourceCommit", {}).get("committedDate", "")[:16]
        msg        = attrs.get("sourceCommit", {}).get("message", "")[:60]
        icon = "✓" if status == "SUCCEEDED" else ("…" if progress == "RUNNING" else "✗")
        print(f"  {icon} {status:<16} {started_at}  {msg}")

if not any_builds:
    print("\nNo builds found. Xcode Cloud may not have triggered yet.")
    print("Check that workflows are set to trigger on tag push in App Store Connect.")
