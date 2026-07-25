---
name: zeroclaw-mcp
description: Provisions MCP servers for ZeroClaw agents - adding server definitions, grouping them into bundles, and granting bundles to specific agents. Use when asked to add an MCP server, give an agent access to an MCP tool, revoke an MCP grant, or diagnose why an agent cannot see MCP tools. MCP in ZeroClaw v0.8.3 is configured entirely through config; there is no mcp subcommand.
---

# Provisioning MCP servers

Verified against **ZeroClaw v0.8.3**. Assumes the session runs on the same host
as the daemon.

**There is no `zeroclaw mcp` subcommand at v0.8.3.** MCP is configured entirely
through `zeroclaw config`. If you reach for `zeroclaw mcp add`, stop — it does
not exist.

For alias rules see `zeroclaw-orientation`; this skill uses the four-beat
mutation loop from `zeroclaw-agents` (read → dry-run → apply → reload and verify).

## The grant chain

Access flows through three levels, and **all three are required**:

```text
[mcp.servers]           the server definition (how to reach it)
      ▼
[mcp_bundles.<alias>]   a named group of server names
      ▼
agents.<alias>.mcp_bundles   which bundles this agent gets
```

**This is default-deny.** `Config::mcp_servers_for_agent` returns an empty list
for an agent with no `mcp_bundles`. Defining a server grants nothing on its own —
it must be in a bundle, and the agent must reference that bundle. This is the
single most common reason an agent "can't see" an MCP server.

## Check the current state first

```sh
zeroclaw config get mcp.enabled
zeroclaw config list --filter mcp
zeroclaw config get agents.<alias>.mcp_bundles
```

If `mcp.enabled` is false, no MCP tools load at all regardless of grants.

## Adding a server

**Step 1 — create the server entry.** This is the step that trips people up.

`mcp.servers` is a **`Vec<McpServerConfig>`**, not a map, so a new entry cannot
be conjured with `config set`. All of these **fail** at v0.8.3:

```sh
# Error: Unknown property 'mcp.servers.filesystem.command'
zeroclaw config set mcp.servers.filesystem.command /usr/local/bin/mcp-server

# Error: op[0] `add` on `mcp.servers.-` failed: property path not found in schema
echo '[{"op":"add","path":"/mcp/servers/-","value":{...}}]' | zeroclaw config patch -
```

Two things actually work. Prefer the first:

**(a) The map-key endpoint** — the supported API, requires a bearer token:

```sh
curl -s -X POST -H "Authorization: Bearer $ZC_TOKEN" \
  "http://localhost:42617/api/config/map-key?path=mcp.servers&key=filesystem"
# {"path":"mcp.servers","key":"filesystem","created":true}
```

Both `path` and `key` are required query parameters; omitting either returns
`Failed to deserialize query string`.

**(b) Append the TOML block directly**, then reload:

```toml
[[mcp.servers]]
name = "filesystem"
transport = "stdio"
command = "/usr/local/bin/mcp-server-filesystem"
args = ["--root", "/srv/data"]
```

**Step 1b — now `config set` works.** Once the entry exists, its dotted paths
become addressable and editable:

```sh
zeroclaw config set mcp.servers.filesystem.command /usr/local/bin/mcp-server-filesystem
zeroclaw config list --filter mcp.servers
```

```text
  mcp.servers.filesystem.transport         = stdio       (McpTransport)
  mcp.servers.filesystem.command           = /usr/...    (String)
  mcp.servers.filesystem.args              = ["--root"]  (Vec<String>)
  mcp.servers.filesystem.tool_timeout_secs = <unset>     (Option<u64>)
  mcp.servers.filesystem.pinned_resources  = <unset>     (Vec<String>)
```

Creation and editing are different mechanisms. Remember the distinction.

> Use `config list --filter mcp.servers` to inspect fields — **not**
> `config schema --path mcp.servers`, whose `--path` is ignored at v0.8.3 and
> returns the whole 1.28 MB schema.

**Step 2 — create a bundle and put the server in it.** The bundle alias follows
config alias rules: lowercase, digits, single underscores, **no hyphens**.

```sh
zeroclaw config set mcp_bundles.research.servers '["filesystem"]'
```

**Step 3 — grant the bundle to the agent:**

```sh
zeroclaw config set agents.example_agent.mcp_bundles '["research"]'
```

**Step 4 — reload and verify:**

```sh
curl -X POST http://localhost:42617/admin/reload
curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/tools \
  | jq '.[] | select(.name | startswith("filesystem__"))'
```

MCP tools are namespaced `<server>__<tool>`, so the server name becomes a tool
prefix. Seeing the prefixed tools in `/api/tools` is the proof the grant worked.

> `/api/tools` needs a bearer token — it returns `401` without one, even on
> loopback. See `zeroclaw-introspect` (Discovery step 5) for how to pair and set
> `$ZC_TOKEN`. `/admin/reload` above needs no token from loopback.

## Credentials: `env` and `headers` only, never `args`

`env` and `headers` are marked `#[secret]` in the schema — encrypted at rest and
never readable back. **`args` is not.** A token in `args` is stored in plaintext
and visible in process listings.

```sh
# Correct: secret-handled
zeroclaw config set mcp.servers.github.env.GITHUB_TOKEN
zeroclaw config set mcp.servers.remote_api.headers.Authorization

# WRONG: plaintext, visible in `ps`
zeroclaw config set mcp.servers.github.args '["--token","ghp_..."]'
```

Omitting the value makes the CLI prompt with masked input. Verify with
`zeroclaw config list --secrets`, which reports population, not contents.

## Revoking access

Remove the bundle from the agent, or the server from the bundle:

```sh
zeroclaw config set agents.example_agent.mcp_bundles '[]'
curl -X POST http://localhost:42617/admin/reload
```

A bundle can also carry an `exclude` list, and **deny wins**: a server named in
`exclude` is dropped even if another bundle the agent references grants it. Use
this to carve an exception out of a shared bundle without forking it:

```sh
zeroclaw config set mcp_bundles.restricted.exclude '["shell_server"]'
```

## Security posture

Treat every third-party MCP server as untrusted code running with the daemon's
privileges.

- **Prefer `stdio` with an absolute, pinned executable path.** A bare command
  name resolves through `PATH` and can be shadowed.
- **`pinned_resources` injects server-controlled text into the system prompt.**
  Each URI listed is read via `resources/read` at agent startup and injected as
  untrusted, server-origin context. A server whose resources are pinned can
  influence the agent's instructions. Pin resources only from servers trusted at
  that level, and treat it as a prompt-injection surface.
- **Scope the server, not just the grant.** A filesystem MCP server should be
  launched with its own root argument; do not rely solely on ZeroClaw's policy to
  contain it.
- **`tool_timeout_secs`** bounds per-call time and is hard-capped in validation.
  Set it for servers that can hang.

## When an agent cannot see MCP tools

Walk the chain in order — the break is almost always a missing link:

```sh
zeroclaw config get mcp.enabled                      # 1. MCP on at all?
zeroclaw config list --filter mcp.servers            # 2. server defined?
zeroclaw config list --filter mcp_bundles            # 3. server in a bundle?
zeroclaw config get agents.<alias>.mcp_bundles       # 4. agent has the bundle?
# ^ step 2 is the usual culprit: `config list --filter mcp` showing only
#   mcp.enabled and mcp.deferred_loading means NO servers are defined, and
#   every bundle referencing one grants nothing.
curl -X POST http://localhost:42617/admin/reload     # 5. reloaded since the change?
curl -s -H "Authorization: Bearer $ZC_TOKEN" \
  http://localhost:42617/api/tools | jq              # 6. tools visible now?
zeroclaw security status --agent <alias>             # 7. policy excluding them?
```

Also check `deferred_loading`: when `mcp.deferred_loading` is true, only tool
names are listed in the system prompt and the model must call `tool_search` to
fetch full schemas before invoking a tool. Tools exist but look absent in the
prompt — this is expected, not a fault.

For the full field inventory and transport-specific requirements, read
`references/server-config.md`.
