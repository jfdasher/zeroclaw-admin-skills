# MCP configuration reference (v0.8.3)

Verified against `crates/zeroclaw-config/src/schema.rs` at tag v0.8.3.

## `[mcp]`

| Field | Type | Meaning |
|---|---|---|
| `enabled` | bool | Master switch for MCP tool loading |
| `deferred_loading` | bool | List only tool names in the prompt; model calls `tool_search` for schemas |
| `servers` | list | Server definitions, keyed by name |

The section also accepts the alias `mcpServers` for compatibility.

## `McpServerConfig`

| Field | Type | Secret | Notes |
|---|---|:---:|---|
| `name` | string | | Display name; becomes the tool prefix `<server>__<tool>` |
| `transport` | enum | | Defaults to `stdio` |
| `url` | string? | | Required for HTTP/SSE transports |
| `command` | string | | Executable to spawn for stdio |
| `args` | list | | Command arguments. **Not secret — never put credentials here** |
| `env` | map | **yes** | Environment variables for stdio |
| `headers` | map | **yes** | HTTP headers for HTTP/SSE; typically bearer tokens |
| `tool_timeout_secs` | int? | | Per-call timeout, hard-capped in validation |
| `pinned_resources` | list | | Resource URIs read once at startup, injected into the system prompt as untrusted context |

`pinned_resources` details: each URI is read via `resources/read` on that server
at agent startup. Pins on a server that does not advertise resources, or that the
agent's tool policy denies, are skipped with a warning. They are read once per
run — not refreshed, no subscriptions.

## `[mcp_bundles.<alias>]`

| Field | Type | Meaning |
|---|---|---|
| `servers` | list of strings | MCP server names granted by this bundle |
| `exclude` | list of strings | Names removed from the grant. **Deny wins** across all referenced bundles |

Resolution, per `Config::mcp_servers_for_bundles`: every excluded name across all
referenced bundles is collected first, so an include in one bundle cannot defeat
an exclude in another. The result is the union of `servers` in first-seen order,
skipping excluded names. A server name with no matching `[mcp.servers]` entry
grants nothing.

## Agent fields

| Field | Type | Meaning |
|---|---|---|
| `mcp_bundles` | list of strings | Bundle aliases this agent receives. Empty means **no MCP servers** |
| `acp_enable_mcp` | bool | Initialize this agent's MCP tools when it serves an ACP session |

`Config::mcp_servers_for_agent` returns an empty list for an unknown alias or one
with no `mcp_bundles`. Default-deny is the designed behavior, not a bug.

## Creating versus editing a server entry

`mcp.servers` is a `Vec<McpServerConfig>`. A **new** entry cannot be created with
`config set` or `config patch` — verified against a live v0.8.3 daemon:

| Attempt | Result |
|---|---|
| `config set mcp.servers.<new>.command …` | `Error: Unknown property 'mcp.servers.<new>.command'` |
| `config patch` with `add` on `/mcp/servers/-` | `property path not found in schema: mcp.servers.-` |
| `POST /api/config/map-key?path=mcp.servers&key=<new>` | **works** — `{"created":true}` |
| Appending an `[[mcp.servers]]` TOML block | **works** |

Once the entry exists, `config set mcp.servers.<name>.<field>` edits it normally
and `config list --filter mcp.servers` shows all its fields.

The map-key endpoint requires **both** `path` and `key` as query parameters;
omitting either yields `Failed to deserialize query string: missing field …`.

## Setting list and map values from the CLI

List-valued fields take a JSON array; map-valued fields are addressed per key:

```sh
zeroclaw config set mcp_bundles.research.servers '["filesystem","github"]'
zeroclaw config set mcp.servers.github.env.GITHUB_TOKEN
```

Note that `mcp_bundles.<alias>` **is** a proper map, so `config set` creates
those aliases directly — unlike `mcp.servers`. This asymmetry between the two
MCP sections is the single most confusing thing about configuring MCP.

Omitting the value on a secret field triggers a masked interactive prompt. Use
`--no-interactive` in scripts, which requires the value on the command line.
