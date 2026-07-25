# Live-instance claim tests

`validate.sh` at the repo root checks structure. These scripts check *truth*:
they run the commands the skills recommend against a real ZeroClaw daemon and
assert the documented behavior actually happens.

## Running

Copy to a host running ZeroClaw and execute there. They assume the binary is at
`~/.cargo/bin/zeroclaw` and the gateway is on `localhost:42617`.

```sh
scp tests/live-claims-round3.sh <host>:~/
ssh <host> bash ~/live-claims-round3.sh
```

**Round 2 and 3 mutate config.** They create scratch agents, MCP servers, and
skill bundles, then clean up after themselves. Back up `~/.zeroclaw` first:

```sh
systemctl --user stop zeroclaw
tar czf ~/zeroclaw-backup-$(date +%F).tar.gz -C ~ .zeroclaw
systemctl --user start zeroclaw
```

## The rounds

| Script | Covers |
|---|---|
| `live-claims-round1.sh` | Broad first pass: introspection, alias grammar, agent CRUD, MCP schema, skills CLI, reload |
| `live-claims-round2.sh` | Corrected gateway auth, secret masking, MCP grant chain end to end, skill-bundle workflow end to end |
| `live-claims-round3.sh` | Regression cover for the three defects live testing found (see `../COMPATIBILITY.md`) |

Round 1 found the auth defect. Round 2 found the `mcp.servers` creation defect.
Round 3 is the guard against both returning.

## A note on pairing

These scripts call `POST /admin/paircode/new` and `POST /pair`, and **every call
persists a new bearer token** into `gateway.paired_tokens`. Running them
repeatedly accumulates live credentials. To revoke them afterward, restore the
`paired_tokens` line from your backup and reload:

```sh
curl -X POST http://localhost:42617/admin/reload
```
