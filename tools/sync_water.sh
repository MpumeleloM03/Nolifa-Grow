#!/bin/zsh
# Fetches the DWS weekly State of Dams page (KwaZulu-Natal) and hands it to the
# water-dams function. Run it from a South African connection: DWS answers 403 to
# data-centre addresses abroad. Safe to run any time; it only adds a reading when
# DWS has published a new week.
#
# Needs NOTIFY_SECRET in ~/.nolifa_sync (one line: NOTIFY_SECRET=...).
set -e
source "$HOME/.nolifa_sync"
FN="https://ysjitrdzraofzfqhbcfp.supabase.co/functions/v1/water-dams"
PAGE=$(mktemp)
trap 'rm -f "$PAGE"' EXIT
curl -sf -m 40 -A "Nolifa/1.0 (community water radar)" \
  "https://www.dws.gov.za/Hydrology/Weekly/ProvinceWeek.aspx?region=KN" -o "$PAGE"
python3 -c 'import json,sys; print(json.dumps({"html": open(sys.argv[1], encoding="utf-8", errors="ignore").read()}))' "$PAGE" |
  curl -s -m 60 -X POST "$FN" -H "x-notify-secret: $NOTIFY_SECRET" -H "Content-Type: application/json" --data-binary @-
echo
