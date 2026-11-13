#!/usr/bin/env bash
# Prove a profile switch never puts the profile token or an env.* secret in
# any child process's argv. Every executable in /usr/bin is fronted by a
# logging wrapper on PATH, so this covers the settings-write jq invocation
# and anything else the switch execs, not just curl.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWAP="$ROOT/bin/skal-swap"
[[ -x $SWAP ]] || { echo "missing $SWAP" >&2; exit 1; }

API_TOKEN='skal-swap-test-api-token-5E19D0A2'
ENV_SECRET='skal-swap-test-env-secret-9C41B7E6'

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# One logger, symlinked under every /usr/bin name. It uses builtins only and
# execs the real binary by absolute path, so it never recurses into itself.
wrap=$workdir/wrap
mkdir -p "$wrap"
export ARGV_LOG=$workdir/argv.log
: >"$ARGV_LOG"
cat >"$workdir/logger" <<'SH'
#!/usr/bin/bash
n=${0##*/}
{ printf '%s' "$n"; printf ' %s' "$@"; printf '\n'; } >>"$ARGV_LOG"
exec -a "$n" "/usr/bin/$n" "$@"
SH
chmod 755 "$workdir/logger"
for bin in /usr/bin/*; do
    name=${bin##*/}
    [[ -f $bin && -x $bin ]] || continue
    case $name in bash | sh | env) continue ;; esac
    ln -s "$workdir/logger" "$wrap/$name"
done

export HOME=$workdir/home
mkdir -p "$HOME/.claude"
export CCS_PROFILES=$workdir/profiles.conf
export CCS_SETTINGS=$HOME/.claude/settings.json
export CCS_CREDS=$HOME/.claude/.credentials.json
export CCS_CLAUDE_JSON=$HOME/.claude.json
export CCS_STATE=$workdir/state
export CCS_CRED_DIR=$workdir/cred
export CCS_HOMES=$workdir/homes
export CCS_MODELS_TTL=0
printf '{"env":{"ANTHROPIC_MODEL":"stale"}}\n' >"$CCS_SETTINGS"
printf '{}\n' >"$CCS_CLAUDE_JSON"

# 127.0.0.1:9 (discard) refuses at once, so the catalogue lookup inside the
# switch fails fast and the switch proceeds without a model list.
cat >"$CCS_PROFILES" <<EOF
[probe]
name = Probe
base_url = http://127.0.0.1:9
token = ${API_TOKEN}
env.PROBE_SECRET = ${ENV_SECRET}
EOF
chmod 600 "$CCS_PROFILES"

PATH="$wrap:$PATH" "$SWAP" use probe >/dev/null 2>&1 || {
    echo "FAIL: skal-swap use probe exited non-zero" >&2
    PATH="$wrap:$PATH" "$SWAP" use probe >&2 || true
    exit 1
}
PATH="$wrap:$PATH" "$SWAP" status >/dev/null 2>&1 || true
PATH="$wrap:$PATH" "$SWAP" status --json >/dev/null 2>&1 || true

grep -q '^jq ' "$ARGV_LOG" || { echo "FAIL: no jq invocation was observed; the wrapper isn't on the path" >&2; exit 1; }

fail=0
for needle in "$API_TOKEN" "$ENV_SECRET"; do
    if grep -F -- "$needle" "$ARGV_LOG" >/dev/null; then
        echo "FAIL: secret reached a child's argv:" >&2
        grep -F -- "$needle" "$ARGV_LOG" | cut -c1-200 >&2
        fail=1
    fi
done

# The switch must still have written the secrets where they belong.
tok=$(/usr/bin/jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$CCS_SETTINGS")
sec=$(/usr/bin/jq -r '.env.PROBE_SECRET // empty' "$CCS_SETTINGS")
stale=$(/usr/bin/jq -r '.env.ANTHROPIC_MODEL // empty' "$CCS_SETTINGS")
[[ $tok == "$API_TOKEN" ]] || { echo "FAIL: settings.json lacks the profile token" >&2; fail=1; }
[[ $sec == "$ENV_SECRET" ]] || { echo "FAIL: settings.json lacks the env.* secret" >&2; fail=1; }
[[ -z $stale ]] || { echo "FAIL: a stale managed key survived the switch" >&2; fail=1; }

if ((fail)); then exit 1; fi
echo "ok: $(wc -l <"$ARGV_LOG") child processes, $(grep -c '^jq ' "$ARGV_LOG") jq calls, no secret in any argv"
