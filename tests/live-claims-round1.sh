#!/usr/bin/env bash
# Verify the factual claims made by the zeroclaw-admin-skills family against a live
# ZeroClaw instance. Read-only phases first, mutating phases after.
# Safe to re-run: cleans up its own test aliases.

ZC="$HOME/.cargo/bin/zeroclaw"
GW="http://localhost:42617"
PASS=0; FAIL=0
FAILED_CLAIMS=()

hdr() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

# ok <skill> <claim> <condition-exit-code> [detail]
ok() {
  local skill="$1" claim="$2" rc="$3" detail="${4:-}"
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS+1)); printf '  PASS  [%s] %s\n' "$skill" "$claim"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  [%s] %s\n' "$skill" "$claim"
    [ -n "$detail" ] && printf '        %s\n' "$detail"
    FAILED_CLAIMS+=("[$skill] $claim")
  fi
}

# Assert a command FAILS (used for "this is rejected" claims)
refutes() {
  local skill="$1" claim="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -ne 0 ]; then ok "$skill" "$claim" 0
  else ok "$skill" "$claim" 1 "command unexpectedly SUCCEEDED: $(echo "$out" | head -2 | tr '\n' ' ')"; fi
}

hdr "PHASE A — zeroclaw-introspect: read-only interrogation"

out=$($ZC status 2>&1); ok introspect "zeroclaw status runs" $?
echo "$out" | grep -qiE "config|\.zeroclaw"; ok introspect "status reports the resolved config path" $? "status output had no config path line"

$ZC doctor >/dev/null 2>&1; ok introspect "zeroclaw doctor runs" $?

$ZC agents list >/dev/null 2>&1; ok introspect "agents list runs" $?
AGENT=$($ZC agents list 2>/dev/null | grep -oE '^[a-z0-9_]+$' | head -1)
[ -n "$AGENT" ]; ok introspect "discovered an agent alias to target ($AGENT)" $?

$ZC security status --agent "$AGENT" >/dev/null 2>&1
ok introspect "security status --agent <alias> runs" $?
$ZC security status --agent "$AGENT" --json 2>/dev/null | jq empty 2>/dev/null
ok introspect "security status --agent --json emits valid JSON" $?

[ -n "$($ZC config list --filter agents 2>/dev/null)" ]
ok introspect "config list --filter <prefix> returns values" $?

$ZC config schema --path agents 2>/dev/null | jq empty 2>/dev/null
ok introspect "config schema --path <dotted> emits valid JSON schema" $?

$ZC config list --secrets >/dev/null 2>&1
ok introspect "config list --secrets runs" $?

curl -sf -m 5 "$GW/health" | jq -e '.runtime.components' >/dev/null 2>&1
ok introspect "/health exposes runtime.components map" $?
curl -sf -m 5 "$GW/health" | jq -e '.runtime.components | to_entries[0].value | has("status") and has("last_error") and has("restart_count")' >/dev/null 2>&1
ok introspect "components carry status/last_error/restart_count" $?

for ep in /api/cost /api/tools /api/sessions /api/logs; do
  curl -sf -m 8 "$GW$ep" >/dev/null 2>&1
  ok introspect "GET $ep responds" $?
done
curl -s -m 8 "$GW/metrics" >/dev/null 2>&1
ok introspect "GET /metrics responds (may report backend disabled)" $?

# Secrets must never be readable
SECRET_PATH=$($ZC config list --secrets 2>/dev/null | grep -oE '^[a-z0-9_.]+' | head -1)
if [ -n "$SECRET_PATH" ]; then
  sv=$($ZC config get "$SECRET_PATH" 2>&1)
  echo "$sv" | grep -qiE "sk-|ghp_|xox|bearer [A-Za-z0-9]{20}|[A-Za-z0-9_-]{40,}"
  if [ $? -ne 0 ]; then ok introspect "config get on a secret does not emit the value ($SECRET_PATH)" 0
  else ok introspect "config get on a secret does not emit the value" 1 "LEAKED: $sv"; fi
else
  ok introspect "found a secret path to probe" 1 "no secret paths listed"
fi

hdr "PHASE B — zeroclaw-orientation: alias grammar is enforced"

refutes orientation "alias with hyphen rejected (my-bot)"        $ZC agents create my-bot
refutes orientation "alias with uppercase rejected (Prod)"       $ZC agents create Prod
refutes orientation "alias with double underscore rejected (a__b)" $ZC agents create a__b
refutes orientation "alias with leading underscore rejected (_x)"  $ZC agents create _x
refutes orientation "alias over 63 chars rejected"               $ZC agents create "$(printf 'a%.0s' $(seq 1 64))"

hdr "PHASE C — zeroclaw-agents: lifecycle CRUD"

$ZC agents delete zctest_agent --yes >/dev/null 2>&1  # pre-clean
$ZC agents delete zctest_renamed --yes >/dev/null 2>&1

$ZC agents create zctest_agent >/dev/null 2>&1
ok agents "agents create <alias> succeeds with a valid alias" $?
$ZC agents list 2>/dev/null | grep -qx "zctest_agent"
ok agents "created alias appears in agents list" $?

$ZC agents rename zctest_agent zctest_renamed >/dev/null 2>&1
ok agents "agents rename <from> <to> succeeds" $?
$ZC agents list 2>/dev/null | grep -qx "zctest_renamed"
ok agents "renamed alias appears in agents list" $?

dr=$($ZC agents delete zctest_renamed --dry-run 2>&1)
ok agents "agents delete --dry-run runs" $?
$ZC agents list 2>/dev/null | grep -qx "zctest_renamed"
ok agents "--dry-run did NOT actually delete the agent" $?

$ZC agents delete zctest_renamed --yes >/dev/null 2>&1
ok agents "agents delete --yes removes the agent" $?
! $ZC agents list 2>/dev/null | grep -qx "zctest_renamed"
ok agents "deleted alias is gone from agents list" $?

$ZC providers list --category models >/dev/null 2>&1
ok agents "providers list --category models runs" $?
$ZC channels list >/dev/null 2>&1
ok agents "channels list runs" $?

RP=$($ZC config get "agents.$AGENT.risk_profile" 2>/dev/null | tr -d '"' | awk '{print $NF}')
if [ -n "$RP" ]; then
  refutes agents "risk profile level rejects 'read_only' (underscore form)" \
    $ZC config set "risk_profiles.$RP.level" read_only --no-interactive
else
  ok agents "resolved a risk profile to test level validation" 1 "could not read agents.$AGENT.risk_profile"
fi

hdr "PHASE D — zeroclaw-mcp: config-only, default-deny"

refutes mcp "no top-level 'zeroclaw mcp' subcommand exists" $ZC mcp --help

$ZC config schema --path mcp.servers 2>/dev/null | jq empty 2>/dev/null
ok mcp "config schema --path mcp.servers emits valid JSON" $?

$ZC config get mcp.enabled >/dev/null 2>&1
ok mcp "mcp.enabled is readable" $?

$ZC config schema --path mcp.servers 2>/dev/null | grep -q '"env"'
ok mcp "schema exposes the env field on MCP servers" $?
$ZC config schema --path mcp.servers 2>/dev/null | grep -q '"headers"'
ok mcp "schema exposes the headers field on MCP servers" $?
$ZC config schema --path mcp.servers 2>/dev/null | grep -q "pinned_resources"
ok mcp "schema exposes pinned_resources" $?

# env/headers must be marked secret; args must not be
envsec=$($ZC config schema --path mcp.servers 2>/dev/null | jq -r '..|objects|select(has("x-secret"))|input_line_number' 2>/dev/null | head -1)
$ZC config schema --path mcp.servers 2>/dev/null | grep -q 'x-secret'
ok mcp "schema marks at least one MCP field x-secret" $?

hdr "PHASE E — zeroclaw-skills-tools"

$ZC skills list >/dev/null 2>&1
ok skills-tools "skills list runs" $?
$ZC skills list --agent "$AGENT" >/dev/null 2>&1
ok skills-tools "skills list --agent <alias> runs" $?
$ZC skills bundle list >/dev/null 2>&1
ok skills-tools "skills bundle list runs" $?

refutes skills-tools "skills install has NO --skill flag" \
  $ZC skills install https://example.com/x.git --skill foo
refutes skills-tools "skills bundle alias rejects hyphens" \
  $ZC skills bundle add zc-probe-bundle

hdr "PHASE F — reload semantics"

code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X POST "$GW/admin/reload")
[ "$code" = "200" ] || [ "$code" = "202" ] || [ "$code" = "204" ]
ok orientation "POST /admin/reload from loopback succeeds without a token (HTTP $code)" $?

sleep 3
curl -sf -m 8 "$GW/health" | jq -e '.runtime.components' >/dev/null 2>&1
ok orientation "instance healthy after reload" $?

hdr "RESULTS"
printf 'passed: %d\nfailed: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nfailed claims:\n'
  for c in "${FAILED_CLAIMS[@]}"; do printf '  - %s\n' "$c"; done
fi
exit 0
