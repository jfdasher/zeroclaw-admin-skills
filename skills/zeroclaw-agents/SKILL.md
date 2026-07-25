---
name: zeroclaw-agents
description: Creates, wires, renames, and deletes ZeroClaw agents and the provider, channel, and profile aliases they reference. Use when asked to add a new agent, point an agent at a model provider or channel, change an agent's risk or runtime profile, rename or remove an agent, or fix a dangling_reference error. Covers agent lifecycle; use zeroclaw-mcp for MCP grants and zeroclaw-skills-tools for skills.
---

# Managing ZeroClaw agents

Verified against **ZeroClaw v0.8.3**. CLI commands need a shell on the daemon's
host (directly or over SSH); `curl` examples need only reach the gateway, which
is often published through a same-host reverse proxy. See `zeroclaw-introspect`.

For the agent-as-a-join model and alias grammar, see the `zeroclaw-orientation`
skill. For inspecting current state, see `zeroclaw-introspect`.

## `agents` versus `agent`

Two different commands whose names collide. Get this right before anything else:

- **`zeroclaw agents`** (plural) — alias CRUD. Create, list, rename, delete.
- **`zeroclaw agent`** (singular) — *runs* an agent. `zeroclaw agent -a <alias> -m "..."`.

## The mutation loop

Every change in this skill follows the same four beats. Do not skip the fourth.

1. **Read** the current state.
2. **Dry-run** where the command supports it.
3. **Apply.**
4. **Reload and verify.**

Beat 4 exists because `zeroclaw config set` writes the file but does not make the
running daemon adopt it:

```sh
curl -X POST http://localhost:42617/admin/reload
```

Then re-read the value and confirm the runtime agrees.

## Listing what exists

```sh
zeroclaw agents list
zeroclaw providers list
zeroclaw providers list --category models
zeroclaw channels list
zeroclaw channels list --channel-type telegram
```

## Creating an agent

**Order matters.** An agent references providers, profiles, and channels by
alias. If it names one that does not exist, validation fails with
`dangling_reference`. Create the targets first.

**Step 1 — create the provider alias if needed.** Category is one of `models`,
`tts`, `transcription`:

```sh
zeroclaw providers create models anthropic prod
```

That creates `[providers.models.anthropic.prod]` with defaults. Set its key
(secret fields prompt for masked input when the value is omitted):

```sh
zeroclaw config set providers.models.anthropic.prod.api_key
zeroclaw config set providers.models.anthropic.prod.model claude-sonnet-4-5
```

**Step 2 — create the agent:**

```sh
zeroclaw agents create example_agent
```

Aliases are lowercase letters, digits, and single underscores. No hyphens, no
uppercase, no `__`, 63 characters maximum. `zeroclaw agents create my-bot` will
be rejected.

**Step 3 — wire its references:**

```sh
zeroclaw config set agents.example_agent.model_provider anthropic.prod
zeroclaw config set agents.example_agent.risk_profile default
zeroclaw config set agents.example_agent.runtime_profile unbounded
```

To discover the exact field names and current values rather than guessing:

```sh
zeroclaw config list --filter agents.example_agent
```

(Not `config schema --path` — at v0.8.3 that flag is ignored and dumps the whole
1.28 MB schema. See `zeroclaw-introspect`.)

**Step 4 — reload and verify:**

```sh
curl -X POST http://localhost:42617/admin/reload
zeroclaw config list --filter agents.example_agent
zeroclaw security status --agent example_agent
zeroclaw agent -a example_agent -m "hello"
```

The final message is the real test: it exercises the provider wiring end to end.

## Renaming

Rename rewrites every reference to the alias across the config:

```sh
zeroclaw agents rename example_agent analyst
```

The same holds for providers and channels, which take their type/category
positionally:

```sh
zeroclaw providers rename models anthropic prod production
zeroclaw channels rename telegram default main
```

Reload afterward.

## Deleting — confirm first

**Deletion cascades.** It scrubs references to the alias and removes owned state.
Always dry-run, show the user the impact, and get explicit confirmation before
using `--yes`.

```sh
zeroclaw agents delete example_agent --dry-run
```

Report what the dry run says it would scrub. Only after the user confirms:

```sh
zeroclaw agents delete example_agent --yes
curl -X POST http://localhost:42617/admin/reload
```

`providers delete` and `channels delete` carry the same `--dry-run` and `--yes`
flags and the same rule.

The dry run's reference count is the safety check that matters. Removing an
alias that something still points at leaves a `dangling_reference`, so clear the
*references* first — an agent's `channels` list, a peer group, a delegate entry —
and re-run the dry run. **`would scrub 0 reference(s)` is the green light.**

### Doing it over the gateway

`DELETE /api/config/map-key?path=agents&key=<alias>` reaches the **same cascade
engine** as `agents delete`, so it scrubs references identically, and it is the
only route for sections the CLI does not cover (`mcp_bundles`, `skill_bundles`,
`peer_groups`). Two differences that matter:

- **There is no `--dry-run` equivalent.** The endpoint deletes. When a preview
  exists, prefer the CLI.
- **Check the `warnings` array in the response.** It is omitted when empty; when
  present, the config delete succeeded but one or more owned-state side effects
  did not — workspace archive, memory/cron/acp purge, session attribution.
  Inspect the archive directory before reusing the alias, and never report a 200
  carrying warnings as a clean delete.

Agent deletion refuses outright on hard references — an enabled `heartbeat.agent`
or a live ACP session — and **fails closed** if the session store cannot be read.
`POST /api/config/rename-map-key` with `{path, from, to}` is the rename
equivalent. Details in `zeroclaw-introspect`'s `references/gateway-endpoints.md`.

## Fixing `dangling_reference`

The error means an alias reference names a target that does not exist. Find the
broken pointer:

```sh
zeroclaw config list --filter agents
zeroclaw providers list
zeroclaw channels list
```

Compare what the agents reference against what exists. Then either create the
missing target or repoint the reference. Typical causes: a typo, a hyphen in an
alias, or a target deleted without the cascade running.

## Changing autonomy

Autonomy is per-agent, carried on the risk profile the agent references — not set
on the agent directly:

```sh
zeroclaw config get agents.example_agent.risk_profile
zeroclaw config set risk_profiles.<profile>.level supervised
```

Accepted values are `readonly`, `supervised`, `full`. **`read_only` with an
underscore is rejected at config load.**

Changing a shared profile affects **every** agent referencing it. To loosen or
tighten one agent only, create a separate profile and point that agent at it.

For the full reference-creation order and profile field inventory, read
`references/wiring-order.md`.
