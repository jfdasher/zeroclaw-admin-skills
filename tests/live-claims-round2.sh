#!/usr/bin/env bash
# Round 2: re-test the corrected auth procedure, then drive the MCP and
# skill-bundle mutation workflows end to end exactly as the skills describe.
ZC="$HOME/.cargo/bin/zeroclaw"
GW="http://localhost:42617"
PASS=0; FAIL=0; FAILED=()

hdr() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok() {
  local s="$1" c="$2" rc="$3" d="${4:-}"
  if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); printf '  PASS  [%s] %s\n' "$s" "$c"
  else FAIL=$((FAIL+1)); printf '  FAIL  [%s] %s\n' "$s" "$c"; [ -n "$d" ] && printf '        %s\n' "$d"; FAILED+=("[$s] $c"); fi
}
reload() { curl -s -o /dev/null -X POST -m 25 "$GW/admin/reload"; sleep 4; }

hdr "PHASE A2 — corrected gateway authentication procedure"

CODE=$(curl -s -m 8 -X POST "$GW/admin/paircode/new" | jq -r .pairing_code)
[ -n "$CODE" ] && [ "$CODE" != "null" ]; ok introspect "POST /admin/paircode/new mints a code from loopback" $?

ZC_TOKEN=$(curl -s -m 8 -X POST "$GW/pair" -H "X-Pairing-Code: $CODE" | jq -r .token)
[ -n "$ZC_TOKEN" ] && [ "$ZC_TOKEN" != "null" ]; ok introspect "POST /pair with X-Pairing-Code returns a token" $?
[[ "$ZC_TOKEN" == zc_* ]]; ok introspect "token has the documented zc_ prefix" $?

c=$(curl -s -o /dev/null -w '%{http_code}' -m 8 -X POST "$GW/api/pair" -H "X-Pairing-Code: $CODE")
[ "$c" = "415" ]; ok introspect "/api/pair rejects the header-only form with 415 (documented trap)" $? "got $c"

for ep in /api/status /api/cost /api/tools /api/sessions /api/logs /api/health; do
  c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H "Authorization: Bearer $ZC_TOKEN" "$GW$ep")
  [ "$c" = "200" ]; ok introspect "GET $ep returns 200 with bearer token" $? "got $c"
done
c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$GW/api/tools")
[ "$c" = "401" ]; ok introspect "GET /api/tools returns 401 WITHOUT a token (loopback included)" $? "got $c"

hdr "PHASE A3 — secrets are populated-only (corrected probe)"

SP=$($ZC config list --secrets 2>/dev/null | grep -oE '[a-z0-9_]+\.[a-z0-9_.]+' | head -1)
[ -n "$SP" ]; ok introspect "found a secret path to probe ($SP)" $?
if [ -n "$SP" ]; then
  $ZC config get "$SP" 2>&1 | grep -qi "not displayed\|encrypted"
  ok introspect "config get on a secret says value not displayed" $?
  $ZC config get "$SP" --json 2>/dev/null | jq -e 'has("populated") and (has("value")|not)' >/dev/null 2>&1
  ok introspect "config get --json returns populated with NO value field" $?
fi

hdr "PHASE G — zeroclaw-mcp: full grant chain, end to end"

TESTAGENT=zctest_mcp
$ZC agents delete $TESTAGENT --yes >/dev/null 2>&1
$ZC agents create $TESTAGENT >/dev/null 2>&1; ok mcp "created scratch agent $TESTAGENT" $?

# Default-deny: brand-new agent must have no mcp_bundles
mb=$($ZC config get agents.$TESTAGENT.mcp_bundles 2>/dev/null)
echo "$mb" | grep -qE '^\s*(\[\]|)\s*$|empty|none'
ok mcp "new agent starts with NO mcp_bundles (default-deny)" $? "got: $mb"

# Define a server
$ZC config set mcp.servers.zctestsrv.command /bin/echo --no-interactive >/dev/null 2>&1
ok mcp "config set mcp.servers.<name>.command creates a server entry" $?
$ZC config get mcp.servers.zctestsrv.command 2>/dev/null | grep -q "/bin/echo"
ok mcp "server command reads back correctly" $?

# Bundle it
$ZC config set mcp_bundles.zctestbundle.servers '["zctestsrv"]' --no-interactive >/dev/null 2>&1
ok mcp "config set mcp_bundles.<alias>.servers accepts a JSON array" $?
$ZC config get mcp_bundles.zctestbundle.servers 2>/dev/null | grep -q "zctestsrv"
ok mcp "bundle membership reads back" $?

# Grant to agent
$ZC config set agents.$TESTAGENT.mcp_bundles '["zctestbundle"]' --no-interactive >/dev/null 2>&1
ok mcp "granting a bundle to an agent succeeds" $?
$ZC config get agents.$TESTAGENT.mcp_bundles 2>/dev/null | grep -q "zctestbundle"
ok mcp "grant reads back on the agent" $?

# Exclude wins
$ZC config set mcp_bundles.zctestbundle.exclude '["zctestsrv"]' --no-interactive >/dev/null 2>&1
ok mcp "bundle exclude list accepts a JSON array" $?

reload
curl -sf -m 8 "$GW/health" >/dev/null 2>&1; ok mcp "instance still healthy after MCP config churn + reload" $?

hdr "PHASE H — zeroclaw-skills-tools: bundle workflow end to end"

$ZC skills bundle add zctest_bundle >/dev/null 2>&1
ok skills-tools "skills bundle add <valid_alias> succeeds" $?
$ZC skills bundle list 2>/dev/null | grep -q "zctest_bundle"
ok skills-tools "new bundle appears in skills bundle list" $?
$ZC skills bundle show zctest_bundle >/dev/null 2>&1
ok skills-tools "skills bundle show <alias> runs" $?

$ZC skills add example-skill --bundle zctest_bundle --description "A scratch probe skill for testing" >/dev/null 2>&1
ok skills-tools "skills add <hyphenated-name> --bundle succeeds (skill names allow hyphens)" $?
$ZC skills list --bundle zctest_bundle 2>/dev/null | grep -q "example-skill"
ok skills-tools "new skill appears in skills list --bundle" $?

$ZC config set agents.$TESTAGENT.skill_bundles '["zctest_bundle"]' --no-interactive >/dev/null 2>&1
ok skills-tools "attaching a skill bundle to an agent succeeds" $?
reload
$ZC skills list --agent $TESTAGENT 2>/dev/null | grep -q "example-skill"
ok skills-tools "skills list --agent shows the skill the agent now loads" $?

$ZC skills audit example-skill >/dev/null 2>&1
ok skills-tools "skills audit <name> runs on an installed skill" $?

hdr "PHASE I — cleanup"

$ZC skills bundle remove zctest_bundle --yes >/dev/null 2>&1
ok cleanup "skills bundle remove --yes succeeds" $?
$ZC agents delete $TESTAGENT --yes >/dev/null 2>&1
ok cleanup "scratch agent deleted" $?
$ZC config set mcp_bundles.zctestbundle.servers '[]' --no-interactive >/dev/null 2>&1
$ZC config set mcp_bundles.zctestbundle.exclude '[]' --no-interactive >/dev/null 2>&1
reload
curl -sf -m 8 "$GW/health" | jq -e '.runtime.components' >/dev/null 2>&1
ok cleanup "instance healthy after full cleanup" $?
$ZC agents list 2>/dev/null | grep -qx "$TESTAGENT" && ok cleanup "scratch agent fully gone" 1 "still present" || ok cleanup "scratch agent fully gone" 0

hdr "RESULTS"
printf 'passed: %d\nfailed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && { printf '\nfailed:\n'; for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done; }
exit 0
