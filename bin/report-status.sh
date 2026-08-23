#!/bin/sh
# Report a dtp/tdtp run to the status page at seancheren.com/status.
#
#   sh bin/report-status.sh start  <kind> <target>      -> prints a run id
#   sh bin/report-status.sh finish <id> <status> <severity> <summary>
#
# `kind` is dtp or tdtp, `target` the plan ("core CalMind ChefMind"), `status`
# one of running / ok / failed, `severity` 0 good, 1 deliberate, 2 small issue,
# 3 needs attention. The page colours a run by severity and paints a running
# one purple.
#
# WHY A FILE AND NOT AN ENDPOINT. The status page is a reader; giving it a
# write route would mean an authenticated POST from a shell script, a token to
# keep, and a URL that can change the page. This pushes a JSON file over the
# SAME SSH credentials the site's own deploy uses, into /home/protected — out
# of the web root, so the file is not reachable on its own and the page is its
# only reader.
#
# NOTHING HERE IS ALLOWED TO FAIL A RELEASE. Every failure path warns on
# stderr and exits 0: a dtp that shipped, tagged and pushed must not report
# itself as broken because a status page could not be told about it. That is
# also why `start` prints its id even when the push failed — the caller has a
# `finish` to make, and it should not have to care.
set -e
cd "$(dirname "$0")/.."
PARENT="${MIND_DIR:-$(cd .. && pwd)}"

LOCAL=".status-history.json"     # gitignored; the local copy we edit and push
REMOTE="/home/protected/status/history.json"
KEEP=5                           # "keep the last 5 dtp's" — Sean, 2026-08-22

# The SSH login lives in the SITE's gitignored deploy.conf, never here: this
# repo has no deploy of its own and no business carrying a real account name.
host() {
  for C in "$PARENT/seancheren-site/deploy.conf" "$PARENT/CalMind/server/deploy.conf"; do
    [ -f "$C" ] || continue
    # shellcheck disable=SC1090
    H=$(. "$C" >/dev/null 2>&1; printf '%s' "${HOST:-}")
    [ -n "$H" ] && { printf '%s' "$H"; return 0; }
  done
  return 1
}

push_remote() {
  H=$(host) || { echo "  (status: no deploy.conf with a HOST — not reported)" >&2; return 0; }
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$H" 'mkdir -p /home/protected/status' >/dev/null 2>&1 || {
    echo "  (status: could not reach the server — not reported)" >&2; return 0; }
  scp -q -o BatchMode=yes -o ConnectTimeout=10 "$LOCAL" "$H:$REMOTE" >/dev/null 2>&1 || {
    echo "  (status: the push failed — not reported)" >&2; return 0; }
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$H" "chmod a+r $REMOTE" >/dev/null 2>&1 || true
}

case "${1:-}" in
  start)
    KIND="${2:-dtp}"; TARGET="${3:-?}"
    ID=$(date -u +%Y%m%d%H%M%S)
    WHEN=$(date '+%Y-%m-%d %H:%M %Z')
    python3 - "$LOCAL" "$ID" "$KIND" "$TARGET" "$WHEN" "$KEEP" <<'PY' || true
import json, os, sys
path, rid, kind, target, when, keep = sys.argv[1:7]
try:
    hist = json.load(open(path))
    if not isinstance(hist, list): hist = []
except Exception:
    hist = []
hist = [h for h in hist if h.get('id') != rid]
hist.insert(0, {'id': rid, 'kind': kind, 'target': target, 'started_at': when,
                'finished_at': None, 'status': 'running', 'severity': 0,
                'summary': 'Running now.'})
# Newest first, trimmed. A run left 'running' by a killed shell ages out of the
# list on its own rather than sitting purple for ever.
hist.sort(key=lambda h: h.get('id', ''), reverse=True)
json.dump(hist[:int(keep)], open(path, 'w'), indent=1)
PY
    push_remote
    printf '%s' "$ID"
    ;;
  finish)
    ID="${2:-}"; STATUS="${3:-ok}"; SEV="${4:-0}"; shift 4 2>/dev/null || shift $#
    SUMMARY="$*"
    [ -n "$ID" ] || { echo "  (status: finish without an id — not reported)" >&2; exit 0; }
    WHEN=$(date '+%Y-%m-%d %H:%M %Z')
    python3 - "$LOCAL" "$ID" "$STATUS" "$SEV" "$WHEN" "$SUMMARY" <<'PY' || true
import json, sys
path, rid, status, sev, when, summary = sys.argv[1:7]
try:
    hist = json.load(open(path))
    if not isinstance(hist, list): hist = []
except Exception:
    hist = []
for h in hist:
    if h.get('id') == rid:
        h.update({'finished_at': when, 'status': status,
                  'severity': int(sev), 'summary': summary or 'No summary recorded.'})
        break
json.dump(hist, open(path, 'w'), indent=1)
PY
    push_remote
    ;;
  *)
    echo "usage: report-status.sh start <kind> <target> | finish <id> <status> <severity> <summary>" >&2
    exit 2
    ;;
esac
exit 0
