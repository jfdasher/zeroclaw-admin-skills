---
name: zeroclaw-orientation
description: Explains what ZeroClaw is and how its configuration model works - the agent-as-a-join model, the alias reference graph, alias naming rules, and the on-disk install layout. Use when someone asks what ZeroClaw is, how agents relate to providers/channels/profiles, what an alias is, or where config and state live. Use for concepts and orientation, NOT for inspecting a running instance (use zeroclaw-introspect for that).
---

# ZeroClaw orientation

Verified against **ZeroClaw v0.8.3**.

This skill is the concepts reference for the ZeroClaw skill family. It requires
no running instance. To inspect a live daemon, use `zeroclaw-introspect`.

## What ZeroClaw is

A single-binary agent runtime written in Rust. You configure it and run it; it
brokers between three things:

- **Model providers** — the LLM endpoints it calls (Anthropic, OpenAI, Ollama,
  and others), configured at `[providers.models.<family>.<alias>]`.
- **Channels** — how the world reaches it (Discord, Telegram, Matrix, Slack,
  email, webhooks, MQTT, a built-in CLI channel), at `[channels.<type>.<alias>]`.
- **Tools** — how it acts (shell, file I/O, HTTP, browser, memory, MCP servers).

Everything runs on the operator's machine with the operator's keys. The
interfaces are the `zeroclaw` CLI, a `zerocode` terminal UI, and an HTTP/WebSocket
gateway (default `localhost:42617`).

## The central idea: an agent is a join

This is the concept that makes the rest of the config legible.

`[agents.<alias>]` is not a program. It is a row that **joins** two halves:

- **Config references it points at but does not own** — a model provider, a risk
  profile, a runtime profile, channels, peer groups, skill/knowledge/MCP bundles,
  cron jobs. Each is a dotted alias. Many agents may point at the same one, or
  diverge freely.
- **Filesystem components it owns** — a workspace directory, a memory backend,
  and an identity/personality source.

```text
  Config references (pointed at)          Filesystem (owned)
  ──────────────────────────────          ──────────────────
  model provider                          workspace/
  risk profile             agents.<alias> memory store
  runtime profile       ──▶  (the join) ◀── identity / personality
  channels
  peer groups
  skill / knowledge / MCP bundles
```

There is no privileged "the agent." The runtime holds a map of agents keyed by
alias; a single-agent install is a map of size one. Every CLI command that drives
an agent must name it: `zeroclaw agent -a <alias> -m "..."`.

Two consequences that explain most confusion:

- **Adding an agent is additive.** Define a new `[agents.<alias>]`, wire its
  references, and it joins the running set. Existing agents are untouched.
- **A reference must exist before something points at it.** Creating an agent
  that names a provider alias which does not exist fails validation with the
  stable error code `dangling_reference`.

## Alias grammar

Config aliases — agents, providers, channels, skill bundles, MCP bundles — are
validated by `validate_alias_key`:

- Lowercase letters, digits, and single underscores only
- Must start and end with a lowercase letter or digit
- Must **not** contain `__` (reserved as the environment-variable path separator)
- Maximum 63 characters
- **Hyphens and uppercase are rejected**

Valid: `prod_v2`, `staging_api`, `assistant`, `bot1`
Invalid: `my-bot` (hyphen), `Prod` (uppercase), `a__b` (double underscore), `_x` (leading underscore)

> **Two namespaces, opposite rules.** ZeroClaw *skill directory names* are a
> different namespace and require lowercase **with hyphens** (`code-review`).
> Config aliases forbid hyphens. `zeroclaw skills bundle add --help` describes
> its alias as "lowercase + hyphens" — that help text is wrong; the alias goes
> through `validate_alias_key` and hyphens are rejected.

## Where things live

```text
~/.zeroclaw/config.toml     the entire configuration
~/.zeroclaw/.secret_key     master key for encrypted secrets — BACK THIS UP
~/.zeroclaw/data/
├── memory/                 SQLite: brain.db, audit.db, response_cache.db
├── sessions/               per-session conversation state
└── state/                  scheduler, cost, health
~/.zeroclaw/shared/skills/  skill bundles
```

The config directory resolves in this order (first match wins):
`$ZEROCLAW_CONFIG_DIR`, `$ZEROCLAW_DATA_DIR`, `$ZEROCLAW_WORKSPACE` (deprecated),
the Homebrew prefix on macOS, then `~/.zeroclaw/`. `zeroclaw status` reports
which one it actually resolved.

**Losing `.secret_key` makes every encrypted secret in the config unrecoverable.**

## What runs when the daemon runs

`zeroclaw daemon` is one process containing the gateway listener, channel
pollers and listeners, the cron scheduler, and one agent loop per session.
`zeroclaw gateway` starts only the HTTP gateway.

Two daemons must never share a config directory — memory is SQLite, which is
single-writer. Run separate instances with `--config-dir`.

## Saved is not applied

`zeroclaw config set` writes `config.toml`. It does **not** make the running
daemon adopt the change. Daemon-owned subsystems — channels, providers, the
scheduler, the memory backend — pick up config only after a reload:

```sh
curl -X POST http://localhost:42617/admin/reload
```

Loopback callers need no token. This is why every mutating workflow in this skill
family ends with reload-and-verify rather than stopping at the write.

## The rest of the family

| Skill | Use it for |
|---|---|
| `zeroclaw-introspect` | Inspecting a running instance: status, health, config values, cost, logs |
| `zeroclaw-agents` | Creating, wiring, renaming, deleting agents and their references |
| `zeroclaw-mcp` | Granting MCP servers to agents through config bundles |
| `zeroclaw-skills-tools` | Installing and auditing ZeroClaw's own skills; tool visibility |

For the security model, autonomy levels, and how a risk profile gates tools, read
`references/config-model.md`.
