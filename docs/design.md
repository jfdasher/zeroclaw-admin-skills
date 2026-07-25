# Design: ZeroClaw administration skills

**Status:** approved, pre-implementation
**Date:** 2026-07-25
**Target:** ZeroClaw **v0.8.3**

## Purpose

A family of Claude Code skills that let an operator drive a running ZeroClaw
instance from a Claude Code session: understand what the software is,
interrogate a live instance for runtime state and its own configuration,
manage agents, and provision MCP servers and tooling for new agents so those
agents can do useful work.

These are **Claude Code skills** (`SKILL.md`, invoked via the `Skill` tool),
not ZeroClaw's own agent-skill feature. ZeroClaw has a separate concept also
called "skills" (`SKILL.md`/`SKILL.toml` in bundles, installed with
`zeroclaw skills install`). The two are distinct; `zeroclaw-skills-tools`
below is a Claude Code skill *about* ZeroClaw's skill feature.

## Constraints

- **Vantage point: local.** The operator's session runs on the same host as
  the daemon. The `zeroclaw` binary is on `PATH` and the config directory is
  readable. Skills lead with CLI; the gateway REST surface is the fallback,
  used where the CLI has no equivalent.
- **Version pinned to v0.8.3.** The upstream `master` branch is 173 commits
  ahead of this tag. Every command, flag, config path, and endpoint is
  verified against the v0.8.3 source tree before it is written down. Where
  the mdbook documentation and the code disagree, the code wins.
- **Symlink install.** Skills are symlinked individually from this repo into
  `~/.claude/skills/`. No skill may depend on a path outside its own
  directory.
- **Drift is accepted.** This repo intentionally diverges from
  `zeroclaw/.claude/skills/zeroclaw/`. It is iterated on periodically rather
  than kept in lockstep.

## Repository layout

```
skills/<skill-name>/SKILL.md
skills/<skill-name>/references/*.md
skills/<skill-name>/evals/evals.json
install.sh
README.md
COMPATIBILITY.md
LICENSE
```

`install.sh` symlinks each `skills/<name>` to `~/.claude/skills/<name>`. It
refuses to overwrite an existing non-symlink entry, replaces stale symlinks
under `--force`, and is idempotent.

`COMPATIBILITY.md` records the verified ZeroClaw version and how to re-verify
after an upgrade. Every `SKILL.md` repeats the version pin in its opening
line so a reader never has to guess which binary it was checked against.

## The five skills

### 1. `zeroclaw-orientation`

The concepts hub and router. **Single source of truth for shared concepts**;
the other four link here rather than restating definitions.

Contents: what ZeroClaw is (single-binary agent runtime brokering providers,
channels, and tools); the agent-as-a-join model (`[agents.<alias>]` points at
config references it does not own, and owns filesystem components); the alias
reference graph; alias grammar; the install layout (`config.toml`,
`.secret_key`, `data/`); daemon anatomy; and a routing table to the sibling
skills.

Fires on: "what is ZeroClaw", "explain the config model", "how do agents
relate to providers", and as a prerequisite hop from the other skills.

### 2. `zeroclaw-introspect`

Read-only interrogation of a running instance. Absorbs troubleshooting rather
than spawning a separate skill.

Contents: `zeroclaw status` (resolved config path, provider, model, channels,
memory backend); `zeroclaw doctor`; `zeroclaw security status --agent <alias>
--json` for effective runtime posture; config interrogation via `config list
--filter`, `config get --json`, and `config schema --path <dotted>`; the
`/health` component map (`status`, `last_ok`, `last_error`,
`restart_count`); `/metrics` when the Prometheus backend is enabled; cost via
`/api/cost`; and log access per service manager.

Fires on: "what's my agent doing", "show me its config", "is it healthy",
"why is this channel failing".

### 3. `zeroclaw-agents`

Agent lifecycle and reference wiring.

Contents: the `zeroclaw agents` (alias CRUD) versus `zeroclaw agent` (run one)
distinction, stated first because the names collide; alias grammar;
creation order that avoids `dangling_reference` validation failures (provider
and profile aliases must exist before an agent references them); the parallel
CRUD surfaces for `providers` and `channels`; `agents delete --dry-run`
before `--yes`, and what the cascade scrubs.

Fires on: "create an agent", "wire this agent to a provider", "rename/delete
an agent", "why won't this agent load".

### 4. `zeroclaw-mcp`

MCP server provisioning. There is **no `zeroclaw mcp` subcommand at v0.8.3** —
this is entirely a config-editing workflow.

Contents: the three-step grant path (`[mcp.servers]` entry →
`[mcp_bundles.<alias>]` → `agents.<x>.mcp_bundles`) and the default-deny
property that an agent with no bundles receives zero MCP servers; the
`McpServerConfig` field set (`transport`, `url`, `command`, `args`, `env`,
`headers`, `tool_timeout_secs`, `pinned_resources`); and the security posture.

Security rules stated explicitly, each verified against the schema:

- `env` and `headers` are `#[secret]`; `args` is **not**. Credentials go in
  `env` or `headers`, never in `args`.
- `pinned_resources` reads server-controlled text at agent startup and injects
  it into the system prompt as untrusted context. Treat any server whose
  resources are pinned as able to influence the agent's instructions.
- Third-party MCP servers are untrusted code. Prefer `stdio` with a pinned
  executable path.

Fires on: "add an MCP server", "give this agent access to X MCP", "why can't
my agent see the MCP tools".

### 5. `zeroclaw-skills-tools`

ZeroClaw's own skill feature and tool enablement.

Contents: `skills bundle add` → `skills install --bundle` → `skills audit` →
`skills list --agent` to confirm what the agent actually loads at runtime;
the script-audit gate (`.sh`/`.bash`/`.ps1` and shebang files blocked by
default) and why `skills.allow_scripts` stays off; and the global-directory
trap, where a skill installs successfully and appears in `skills list` but no
agent loads it because it is not attached to a bundle the agent references.

Fires on: "install a skill", "audit this skill", "my agent isn't using the
skill I installed", "what tools does this agent have".

## Cross-cutting doctrine

Every mutating skill (`agents`, `mcp`, `skills-tools`) follows the same
four-beat loop, because ZeroClaw's failure modes are consistent:

1. **Read effective state** before changing it.
2. **Dry-run or diff** where the command supports it.
3. **Apply.**
4. **Reload and re-verify.**

Beat 4 is not optional. `zeroclaw config set` writes the file, but
daemon-owned subsystems (channels, providers, scheduler, memory backend) do
not adopt the change until `POST /admin/reload` — allowed from loopback with
no token — or a service restart. A skill that stops after the write teaches
the wrong reflex. Re-verification means reading the value back and confirming
the runtime reflects it, not just that the file changed.

Two rules apply across all five skills:

- **Never attempt to read a secret back.** Config reads return
  `populated: bool` for secret-marked fields, never a value. Verify with
  `config list --secrets`, which reports population, not contents.
- **`.secret_key` loss is unrecoverable.** Any skill that writes a secret
  states this and points at the backup requirement.

## Mutation posture

Skills execute directly for reads, creates, and grants. They stop and confirm
before destructive operations: `agents delete`, `providers delete`,
`channels delete`, `estop`, and `memory clear`. Confirmation is an explicit
instruction in the skill, not a judgment call left to the model.

## Trigger design

Trigger accuracy lives entirely in the frontmatter `description`. The five
descriptions are written to be mutually disjoint. The likeliest collision is
`orientation` against `introspect`; these are separated by scoping
`orientation` to *concepts and routing* (no live instance required) and
`introspect` to *inspecting a running instance* (requires one).

Each skill ships `evals/evals.json` following the convention already used by
`zeroclaw/.claude/skills/zeroclaw/`, so trigger regressions are detectable
across iterations.

## Verification method

Every command name, flag, config path, endpoint, and default asserted in a
skill is checked against the v0.8.3 source tree — `src/main.rs` and
`src/lib.rs` for the clap surface, `crates/zeroclaw-config/src/schema.rs` for
config paths and secret markers, `crates/zeroclaw-gateway/src/lib.rs` for the
router — before it is written. Claims that cannot be verified are omitted
rather than hedged.

## Out of scope

- ZeroClaw-native agent skills (a `SKILL.toml` bundle installed into the
  instance so the agent self-administers). Considered and set aside.
- Remote/gateway-first operation. The local vantage point is assumed.
- Channel setup beyond what agent wiring requires.
- Any modification to `zeroclaw/.claude/skills/zeroclaw/`.
