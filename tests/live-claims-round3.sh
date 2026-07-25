#!/usr/bin/env bash
# Round 3: verify the CORRECTED procedures, including the ones round 2 broke on.
ZC="$HOME/.cargo/bin/zeroclaw"; GW="http://localhost:42617"
PASS=0; FAIL=0; FAILED=()
hdr(){ printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok(){ local s="$1" c="$2" rc="$3" d="${4:-}"
  if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); printf '  PASS  [%s] %s\n' "$s" "$c"
  else FAIL=$((FAIL+1)); printf '  FAIL  [%s] %s\n' "$s" "$c"; [ -n "$d" ] && printf '        %s\n' "$d"; FAILED+=("[$s] $c"); fi; }
reload(){ curl -s -o /dev/null -X POST -m 25 "$GW/admin/reload"; sleep 4; }

CODE=$(curl -s -m 8 -X POST "$GW/admin/paircode/new" | jq -r .pairing_code)
ZC_TOKEN=$(curl -s -m 8 -X POST "$GW/pair" -H "X-Pairing-Code: $CODE" | jq -r .token)
AUTH=(-H "Authorization: Bearer $ZC_TOKEN")

hdr "corrected: config discovery uses config list --filter, not schema --path"
A=$($ZC agents list 2>/dev/null | grep -oE '^[a-z0-9_]+$' | head -1)
n=$($ZC config list --filter "agents.$A" 2>/dev/null | grep -c "agents.$A")
[ "$n" -gt 3 ]; ok introspect "config list --filter returns scoped paths ($n entries)" $?
a=$($ZC config schema --path agents 2>/dev/null | wc -c)
b=$($ZC config schema --path totally.bogus 2>/dev/null | wc -c)
[ "$a" -gt 1000000 ] && [ "$b" -gt 1000000 ]
ok introspect "config schema --path is confirmed NON-scoping (both ~$((a/1000))KB)" $?
$ZC config schema --path totally.bogus >/dev/null 2>&1
ok introspect "config schema --path with a bogus path exits 0 (documented gotcha)" $?
curl -s "${AUTH[@]}" -m 10 "$GW/api/config/list?prefix=mcp" | jq -e '.entries|length>0' >/dev/null 2>&1
ok introspect "GET /api/config/list?prefix= returns scoped JSON entries" $?

hdr "corrected: MCP server creation via map-key endpoint"
curl -s "${AUTH[@]}" -m 10 -X POST "$GW/api/config/map-key?path=mcp.servers&key=zctestsrv3" | jq -e '.created==true' >/dev/null 2>&1
ok mcp "POST /api/config/map-key?path=&key= creates an mcp.servers entry" $?
$ZC config list --filter mcp.servers 2>/dev/null | grep -q zctestsrv3
ok mcp "created server appears in config list --filter mcp.servers" $?
$ZC config set mcp.servers.zctestsrv3.command /bin/true --no-interactive >/dev/null 2>&1
ok mcp "config set works on the server AFTER the entry exists" $?
$ZC config get mcp.servers.zctestsrv3.command 2>/dev/null | grep -q "/bin/true"
ok mcp "edited value reads back" $?
curl -s "${AUTH[@]}" -m 10 -X POST "$GW/api/config/map-key?path=mcp.servers" 2>&1 | grep -qi "missing field"
ok mcp "map-key without key= is rejected (documented)" $?
$ZC config set mcp.servers.zctestsrv_nope.command /bin/true --no-interactive 2>&1 | grep -qi "unknown property"
ok mcp "config set on a NON-EXISTENT server still fails with Unknown property" $?

hdr "corrected: the diagnostic that catches an inert MCP config"
srv=$($ZC config list --filter mcp.servers 2>/dev/null | grep -c "mcp.servers\.")
echo "        (servers currently defined: $srv field-rows)"
[ "$srv" -gt 0 ]; ok mcp "diagnostic distinguishes 'servers defined' from 'bundles only'" $?

hdr "cleanup"
python3 - <<'PY'
import re
p="$HOME/.zeroclaw/config.toml"
lines=open(p).read().split("\n"); out=[]; skip=False
for i,l in enumerate(lines):
    if l.strip()=="[[mcp.servers]]":
        blk=[];j=i+1
        while j<len(lines) and not lines[j].startswith("["): blk.append(lines[j]);j+=1
        if any("zctestsrv" in b for b in blk): skip=True; continue
        skip=False
    elif l.startswith("[") and skip: skip=False
    if not skip: out.append(l)
open(p,"w").write("\n".join(out))
PY
grep -q zctestsrv $HOME/.zeroclaw/config.toml && ok cleanup "test servers removed" 1 "residue remains" || ok cleanup "test servers removed" 0
reload
curl -sf -m 8 "$GW/health" | jq -e '.runtime.components' >/dev/null 2>&1
ok cleanup "instance healthy after cleanup" $?

hdr "RESULTS"; printf 'passed: %d\nfailed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && { printf '\nfailed:\n'; for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done; }
exit 0
