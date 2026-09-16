#!/usr/bin/env bash
# Prove fetch_models never puts the profile token or OAuth access token in
# curl's argv. Samples /proc/<pid>/cmdline of the live child while a delayed
# local catalogue response keeps curl in flight.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWAP="$ROOT/bin/skal-swap"
[[ -x $SWAP ]] || { echo "missing $SWAP" >&2; exit 1; }

API_TOKEN='skal-swap-test-api-token-A7F3E91C'
OAUTH_TOKEN='skal-swap-test-oauth-token-B2D8C44F'

workdir=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$workdir"' EXIT

port_file=$workdir/port
cmdline_log=$workdir/cmdlines
: >"$cmdline_log"

python3 - "$workdir" "$port_file" "$cmdline_log" "$API_TOKEN" "$OAUTH_TOKEN" <<'PY' &
import json, os, pathlib, socket, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

workdir, port_file, cmdline_log, api_token, oauth_token = sys.argv[1:6]
needles = (api_token.encode(), oauth_token.encode())
body = json.dumps({
    "data": [{
        "id": "claude-opus-4-5",
        "display_name": "Opus",
        "created": 1,
        "max_tokens": 64000,
        "max_input_tokens": 200000,
    }]
}).encode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(0.7)
        auth = self.headers.get("Authorization", "")
        xkey = self.headers.get("X-Api-Key", "")
        allowed = {
            f"Bearer {api_token}",
            f"Bearer {oauth_token}",
        }
        if auth not in allowed and xkey not in {api_token, oauth_token}:
            self.send_response(401)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
port = sock.getsockname()[1]
sock.close()
httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
pathlib.Path(port_file).write_text(str(port))

deadline = time.time() + 20
seen = False
leaks = []
logged = set()
done_path = pathlib.Path(workdir, "done")
while time.time() < deadline:
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = pathlib.Path(f"/proc/{entry}/cmdline").read_bytes()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        args0 = raw.split(b"\0", 1)[0]
        if args0 != b"curl" and not args0.endswith(b"/curl"):
            continue
        if b"--max-filesize" not in raw:
            continue
        seen = True
        if raw in logged:
            continue
        logged.add(raw)
        with open(cmdline_log, "ab") as fh:
            fh.write(raw.replace(b"\0", b" ") + b"\n")
        for needle in needles:
            if needle in raw:
                leaks.append(raw)
    if done_path.exists() and seen:
        break
    time.sleep(0.02)

pathlib.Path(workdir, "poller.json").write_text(json.dumps({
    "seen": seen,
    "leaked": bool(leaks),
}))
httpd.shutdown()
sys.exit(1 if leaks or not seen else 0)
PY
poller_pid=$!

for _ in $(seq 1 50); do
    [[ -s $port_file ]] && break
    sleep 0.02
done
[[ -s $port_file ]] || { echo "test server did not bind" >&2; exit 1; }
port=$(cat "$port_file")

export CCS_PROFILES=$workdir/profiles.conf
export CCS_SETTINGS=$workdir/settings.json
export CCS_CREDS=$workdir/credentials.json
export CCS_CLAUDE_JSON=$workdir/claude.json
export CCS_STATE=$workdir/state
export CCS_CRED_DIR=$workdir/cred
export CCS_MODELS_TTL=0
printf '{"env":{}}\n' >"$CCS_SETTINGS"
printf '{}\n' >"$CCS_CLAUDE_JSON"

run_probe() {
    local label=$1 out
    echo "probe: $label"
    out=$("$SWAP" models "$2" --refresh)
    printf '%s\n' "$out" | grep -q 'claude-opus-4-5' || {
        echo "FAIL: $label catalogue fetch did not return the test model" >&2
        printf '%s\n' "$out" >&2
        exit 1
    }
}

# API-token path: headers used to be -H "authorization: Bearer $tok"
cat >"$CCS_PROFILES" <<EOF
[probe-api]
name = Probe API
base_url = http://127.0.0.1:${port}
token = ${API_TOKEN}
EOF
run_probe api probe-api

# OAuth path: headers used to be -H "authorization: Bearer $tok"
cat >"$CCS_PROFILES" <<EOF
[probe-oauth]
name = Probe OAuth
EOF
printf '{"claudeAiOauth":{"accessToken":"%s"}}\n' "$OAUTH_TOKEN" >"$CCS_CREDS"
export CCS_ANTHROPIC_MODELS_URL="http://127.0.0.1:${port}/v1/models?limit=1000"
run_probe oauth probe-oauth

touch "$workdir/done"
set +e
wait "$poller_pid"
status=$?
set -e

echo "---- observed curl cmdlines ----"
cat "$cmdline_log" || true

if [[ $status -ne 0 ]]; then
    if [[ -f $workdir/poller.json ]]; then
        echo "poller: $(cat "$workdir/poller.json")" >&2
    fi
    echo "FAIL: live curl cmdline missing, or a token appeared in it" >&2
    exit 1
fi

# Belt: the on-disk log must also be clean.
if grep -F -e "$API_TOKEN" -e "$OAUTH_TOKEN" "$cmdline_log"; then
    echo "FAIL: token found in recorded cmdline log" >&2
    exit 1
fi

echo "ok: neither token appeared in live curl cmdline"
