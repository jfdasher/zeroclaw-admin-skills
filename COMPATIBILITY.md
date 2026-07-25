# Compatibility

These skills are verified against **ZeroClaw v0.8.3**.

## Why the pin matters

ZeroClaw's `master` moves fast — it was 173 commits ahead of `v0.8.3` when these
skills were written. The project's own mdbook documentation also leads the code
in places. Two concrete examples found during verification:

- The book documents `zeroclaw skills install <git-url> --skill <name>`. **No
  `--skill` flag exists on `skills install` at v0.8.3.**
- `zeroclaw skills bundle add --help` describes the alias as "lowercase +
  hyphens". The alias is validated by `validate_alias_key`, which **rejects
  hyphens**.

Every command, flag, config path, and endpoint in these skills was checked
against the v0.8.3 source, not the documentation. Where the two disagreed, the
code won.

## Live-instance verification

The skills were subsequently executed against a running v0.8.3 daemon. Reading
the source was not sufficient — three defects survived it and were only caught
by running the commands:

1. **Every `/api/*` route requires a bearer token, even on loopback.** Only
   `/health` and `/metrics` are public. The skills originally showed bare
   `curl http://localhost:42617/api/...`, which returns `401` on any instance
   with the default `require_pairing = true`. Pair via `POST /pair` (**not**
   `/api/pair`, which wants `Content-Type: application/json` and answers the
   header form with `415`). `/admin/reload` is the reverse case — loopback needs
   no token at all.

2. **`config schema --path <dotted>` silently ignores `--path`.** Every
   invocation returns the entire ~1.28 MB whole-config schema, and a nonexistent
   path exits 0 rather than erroring. `OPTIONS /api/config/prop?path=…` has the
   same defect. Use `config list --filter <prefix>` or
   `GET /api/config/list?prefix=<dotted>`, which genuinely scope.

3. **`mcp.servers` is a `Vec`, not a map, so a new server cannot be created with
   `config set`** (`Error: Unknown property`) or with a `config patch` `add` to
   `/mcp/servers/-` (`property path not found in schema`). Create the entry with
   `POST /api/config/map-key?path=mcp.servers&key=<name>` (both query parameters
   required) or by appending an `[[mcp.servers]]` TOML block. *After* the entry
   exists, `config set mcp.servers.<name>.<field>` edits it normally.
   `mcp_bundles.<alias>` **is** a real map and does accept `config set` directly
   — this asymmetry between the two MCP sections is the main trap.

Confirmed working as documented: the alias grammar (all five rejection cases),
agent create/rename/delete with `--dry-run` not deleting, `read_only` rejection,
secrets returning `populated` with no value, the absence of a `zeroclaw mcp`
subcommand, the absent `--skill` flag, hyphen rejection on bundle aliases, and
the full skill-bundle workflow through `skills list --agent`.

## Re-verifying after a ZeroClaw upgrade

Create a worktree at the new tag and re-check the surfaces the skills depend on:

```sh
git -C /path/to/zeroclaw worktree add --detach /tmp/zc-check vX.Y.Z
cd /tmp/zc-check

# CLI surface
grep -n "enum Commands" -A 400 src/main.rs
grep -n "enum AgentsCommands\|enum SkillCommands\|enum SkillBundleCommands" -A 60 src/lib.rs
grep -n "enum ConfigCommands" -A 100 src/main.rs

# Config schema: MCP, secrets, alias grammar
grep -n "pub struct McpServerConfig" -A 45 crates/zeroclaw-config/src/schema.rs
grep -n "pub struct McpBundleConfig" -A 10 crates/zeroclaw-config/src/schema.rs
grep -n "fn validate_alias_key" -A 45 crates/zeroclaw-config/src/helpers.rs

# Gateway routes
grep -oE '\.route\("[^"]+"' crates/zeroclaw-gateway/src/lib.rs | sort -u
```

Update the pin in `validate.sh` (`PIN=`), in this file, and in each
`SKILL.md` opening line, then run `./validate.sh`.
