# ZeroClaw Administration Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build five Claude Code skills in `~/prj/zeroclaw-admin-skills` that let an operator explain, interrogate, and administer a local ZeroClaw v0.8.3 instance, installed by symlink into `~/.claude/skills/`.

**Architecture:** A skill-only repository. Each skill is a self-contained directory under `skills/` holding `SKILL.md`, an optional `references/` directory loaded on demand, and `evals/evals.json`. A `validate.sh` script enforces structural invariants and acts as the test harness. An `install.sh` script symlinks skills into `~/.claude/skills/`. `zeroclaw-orientation` is the single source for shared concepts; the other four link to it rather than restating definitions.

**Tech Stack:** Markdown with YAML frontmatter, POSIX shell (`bash`), `jq` for eval validation, `git`.

## Global Constraints

- **Target ZeroClaw version: v0.8.3.** Every command, flag, config path, endpoint, and default asserted in a skill MUST be verified against the v0.8.3 source tree before it is written. Where the mdbook documentation and the code disagree, the code wins.
- **Verification worktree:** `/tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083` (a detached `git worktree` at tag `v0.8.3`). If absent, recreate with: `git -C ~/prj/zeroclaw worktree add --detach <path> v0.8.3`
- **Vantage point: local.** The operator's Claude Code session runs on the same host as the daemon. Skills lead with the `zeroclaw` CLI; REST is used only where the CLI has no equivalent.
- **Repo root:** `~/prj/zeroclaw-admin-skills`, branch `main`.
- **No `Co-Authored-By` lines or self-credits in commit messages.** (User's global preference.)
- **Mutation posture:** skills execute reads, creates, and grants directly; they stop and require explicit confirmation before `agents delete`, `providers delete`, `channels delete`, `skills bundle remove`, `estop`, and `memory clear`.
- **Claims that cannot be verified are omitted, not hedged.**

## Verified reference data

This data was verified against v0.8.3 during planning. Use it directly; re-verify only if a step says to.

**Top-level CLI subcommands** (`src/main.rs`, `enum Commands`): `quickstart`, `onboard`, `agent`, `gateway`, `acp`, `daemon`, `service`, `doctor`, `status`, `security`, `estop`, `cron`, `models`, `providers`, `channel`, `agents`, `channels`, `integrations`, `skills`, `browse`, `sop`, `migrate`, `auth`, `hardware`, `peripheral`, `memory`, `config`.

**Alias grammar** (`crates/zeroclaw-config/src/helpers.rs`, `validate_alias_key`): lowercase letters, digits, and single underscores only. Must start and end with a lowercase letter or digit. Must not contain `__` (reserved as the env-var path separator). Maximum 63 characters. **Hyphens are rejected.** Applies to agent, provider, channel, skill-bundle, and MCP-bundle aliases.

**ZeroClaw skill directory names** are a different namespace: `skills add` requires lowercase + hyphens. Do not confuse the two.

**`zeroclaw agents`** (`src/lib.rs`, `enum AgentsCommands`): `list`, `create <alias>`, `rename <from> <to>`, `delete <alias> [--dry-run] [--yes]`.

**`zeroclaw providers`** (`enum ProvidersCommands`): `list [--category <models|tts|transcription>]`, `create <category> <family> <alias>`, `rename <category> <family> <from> <to>`, `delete <category> <family> <alias> [--dry-run] [--yes]`.

**`zeroclaw channels`** (`enum ChannelsCommands`): `list [--channel-type <type>]`, `create <channel_type> <alias>`, `rename <channel_type> <from> <to>`, `delete ... [--dry-run] [--yes]`.

**`zeroclaw config`** (`src/main.rs`, `enum ConfigCommands`): `schema [--path <dotted>]`, `list [-f|--filter <prefix>] [--secrets]`, `get <path> [--json]`, `set <path> [value] [--no-interactive] [--comment <text>] [--json]`, `init [section] [--json]`, `migrate [--json]`, `patch [input|-] [--json]`, `docs`, `generate [version] [--encrypt]`.

**`zeroclaw security`** (`enum SecurityCommands`): `status --agent <alias> [--json]`.

**`zeroclaw skills`** (`src/lib.rs`, `enum SkillCommands`): `list [--agent <alias>] [--bundle <alias>]`, `add <name> [--bundle] [--description] [--license] [--author] [--version] [--category] [--no-scaffold] [--edit]`, `edit <name> [--bundle] [--file]`, `bundle <op>`, `audit <source>`, `install <source> [--agent] [--bundle] [--no-tier-banner]`, `remove <name> [--agent] [--bundle]`, `test [name] [--verbose]`.

**IMPORTANT:** `skills install` at v0.8.3 has **no `--skill` flag**, despite the mdbook documenting `--skill find-skills`. Do not write it.

**`zeroclaw skills bundle`** (`enum SkillBundleCommands`): `list`, `add <alias> [--directory <path>]`, `remove <alias> [--yes]`, `rename <from> <to>`, `show <alias>`. The `Add` help text says "lowercase + hyphens"; this is **incorrect** — the alias goes through `validate_alias_key`, which rejects hyphens.

**Gateway routes** (`crates/zeroclaw-gateway/src/lib.rs`): `/health`, `/api/health`, `/api/status`, `/api/cost`, `/metrics`, `/admin/reload`, `/admin/shutdown`, `/api/tools`, `/api/config`, `/api/config/prop`, `/api/config/list`, `/api/config/drift`, `/api/config/migrate`, `/api/memory`, `/api/cron`, `/api/events`, `/api/events/history`, `/api/sessions`, `/api/skills/bundles`, `/api/logs`, `/api/channels`, `/api/docs`, `/api/openapi.json`.

**MCP config** (`crates/zeroclaw-config/src/schema.rs`):
- `[mcp]` → `enabled: bool`, `deferred_loading: bool`, `servers: Vec<McpServerConfig>`
- `McpServerConfig` → `name`, `transport` (default `stdio`), `url`, `command`, `args`, `env` (**`#[secret]`**), `headers` (**`#[secret]`**), `tool_timeout_secs`, `pinned_resources`
- `[mcp_bundles.<alias>]` → `servers: Vec<String>`, `exclude: Vec<String>` — **deny wins**: a name in `exclude` is dropped even if another referenced bundle grants it
- `agents.<alias>.mcp_bundles: Vec<String>`, `agents.<alias>.acp_enable_mcp: bool`
- `Config::mcp_servers_for_agent` returns **no servers** for an agent with no `mcp_bundles`. Default-deny.

**There is no `zeroclaw mcp` subcommand at v0.8.3.** MCP provisioning is config editing only.

---

### Task 1: Repository scaffolding and validation harness

**Files:**
- Create: `~/prj/zeroclaw-admin-skills/.gitignore`
- Create: `~/prj/zeroclaw-admin-skills/README.md`
- Create: `~/prj/zeroclaw-admin-skills/COMPATIBILITY.md`
- Create: `~/prj/zeroclaw-admin-skills/LICENSE`
- Create: `~/prj/zeroclaw-admin-skills/install.sh`
- Create: `~/prj/zeroclaw-admin-skills/validate.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `validate.sh` — exits 0 when every directory under `skills/` satisfies the structural invariants, non-zero otherwise. Every later task runs it as its test. `install.sh` — symlinks `skills/*` into `~/.claude/skills/`.

- [ ] **Step 1: Write the failing test (the validator)**

Create `~/prj/zeroclaw-admin-skills/validate.sh`:

```bash
#!/usr/bin/env bash
# Structural validation for the zeroclaw-admin-skills repo.
# Exits 0 if every skill is well-formed, 1 otherwise.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
PIN="ZeroClaw v0.8.3"
EXPECTED_SKILLS=(
  zeroclaw-orientation
  zeroclaw-introspect
  zeroclaw-agents
  zeroclaw-mcp
  zeroclaw-skills-tools
)

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

[ -d "$SKILLS_DIR" ] || { err "skills/ directory does not exist"; exit 1; }

for name in "${EXPECTED_SKILLS[@]}"; do
  dir="$SKILLS_DIR/$name"
  skill_md="$dir/SKILL.md"

  if [ ! -d "$dir" ]; then
    err "$name: directory missing"
    continue
  fi
  if [ ! -f "$skill_md" ]; then
    err "$name: SKILL.md missing"
    continue
  fi

  # Frontmatter must be delimited by --- on line 1 and a later ---.
  if [ "$(head -n 1 "$skill_md")" != "---" ]; then
    err "$name: SKILL.md does not start with '---'"
    continue
  fi
  fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$skill_md")"
  if [ -z "$fm_end" ]; then
    err "$name: SKILL.md frontmatter is not terminated"
    continue
  fi
  fm="$(sed -n "2,$((fm_end - 1))p" "$skill_md")"

  fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1)"
  fm_desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n 1)"

  [ -n "$fm_name" ] || err "$name: frontmatter missing 'name'"
  [ -n "$fm_desc" ] || err "$name: frontmatter missing 'description'"
  [ "$fm_name" = "$name" ] || err "$name: frontmatter name '$fm_name' != directory name"

  # Description must be substantial enough to drive triggering.
  if [ -n "$fm_desc" ] && [ "${#fm_desc}" -lt 40 ]; then
    err "$name: description is too short (${#fm_desc} chars, need >= 40)"
  fi

  # Version pin must appear in the body.
  if ! grep -qF "$PIN" "$skill_md"; then
    err "$name: body does not state the '$PIN' version pin"
  fi

  # Evals must exist and be valid JSON.
  evals="$dir/evals/evals.json"
  if [ ! -f "$evals" ]; then
    err "$name: evals/evals.json missing"
  elif ! jq empty "$evals" 2>/dev/null; then
    err "$name: evals/evals.json is not valid JSON"
  fi
done

# The forbidden-flag check: --skill does not exist on `skills install` at v0.8.3.
if grep -rn -- "skills install.*--skill " "$SKILLS_DIR" 2>/dev/null; then
  err "found 'skills install --skill', which does not exist at $PIN"
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: all %d skills valid\n' "${#EXPECTED_SKILLS[@]}"
fi
exit "$fail"
```

Make it executable:

```bash
chmod +x ~/prj/zeroclaw-admin-skills/validate.sh
```

- [ ] **Step 2: Run the validator to verify it fails**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: `FAIL: skills/ directory does not exist` on stderr and `exit=1`.

- [ ] **Step 3: Create the skills directory and confirm the failure mode changes**

```bash
mkdir -p ~/prj/zeroclaw-admin-skills/skills
```

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: five `FAIL: <name>: directory missing` lines and `exit=1`. This confirms the validator enumerates all five expected skills.

- [ ] **Step 4: Write `install.sh`**

Create `~/prj/zeroclaw-admin-skills/install.sh`:

```bash
#!/usr/bin/env bash
# Symlink every skill in this repo into ~/.claude/skills/.
# Usage: ./install.sh [--force] [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/skills"
DEST_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

force=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --force)   force=1 ;;
    --dry-run) dry_run=1 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

[ -d "$SRC_DIR" ] || { printf 'no skills/ directory at %s\n' "$SRC_DIR" >&2; exit 1; }
mkdir -p "$DEST_DIR"

status=0
for src in "$SRC_DIR"/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  src="${src%/}"
  dest="$DEST_DIR/$name"

  if [ -L "$dest" ]; then
    current="$(readlink "$dest")"
    if [ "$current" = "$src" ]; then
      printf 'ok       %s (already linked)\n' "$name"
      continue
    fi
    if [ "$force" -eq 1 ]; then
      [ "$dry_run" -eq 1 ] || { rm "$dest"; ln -s "$src" "$dest"; }
      printf 'relinked %s -> %s\n' "$name" "$src"
      continue
    fi
    printf 'SKIP     %s: stale symlink to %s (use --force)\n' "$name" "$current" >&2
    status=1
    continue
  fi

  if [ -e "$dest" ]; then
    printf 'SKIP     %s: exists and is not a symlink; refusing to replace\n' "$name" >&2
    status=1
    continue
  fi

  [ "$dry_run" -eq 1 ] || ln -s "$src" "$dest"
  printf 'linked   %s -> %s\n' "$name" "$src"
done

exit "$status"
```

Make it executable:

```bash
chmod +x ~/prj/zeroclaw-admin-skills/install.sh
```

- [ ] **Step 5: Test `install.sh` against a throwaway destination**

Run:

```bash
cd ~/prj/zeroclaw-admin-skills
mkdir -p skills/zeroclaw-orientation
TMPDEST="$(mktemp -d)"
CLAUDE_SKILLS_DIR="$TMPDEST" ./install.sh
CLAUDE_SKILLS_DIR="$TMPDEST" ./install.sh
mkdir -p "$TMPDEST/blocker" && CLAUDE_SKILLS_DIR="$TMPDEST" ./install.sh; echo "exit=$?"
ls -l "$TMPDEST"
rm -rf "$TMPDEST"
rmdir skills/zeroclaw-orientation
```

Expected: first run prints `linked   zeroclaw-orientation -> ...`; second run prints `ok       zeroclaw-orientation (already linked)` (idempotent); the run after creating `blocker/` still succeeds for the symlink and exits 0, because `blocker` is not in `skills/`. `ls -l` shows one symlink.

- [ ] **Step 6: Write `.gitignore`, `LICENSE`, `README.md`, and `COMPATIBILITY.md`**

Create `~/prj/zeroclaw-admin-skills/LICENSE` (MIT, matching the permissive
posture of a shareable skills repo):

```text
MIT License

Copyright (c) 2026 James Dasher

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Create `~/prj/zeroclaw-admin-skills/.gitignore`:

```gitignore
*.swp
.DS_Store
```

Create `~/prj/zeroclaw-admin-skills/README.md`:

```markdown
# zeroclaw-admin-skills

Claude Code skills for operating a [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw)
instance: understanding it, interrogating it, managing agents, and provisioning
MCP servers and tooling.

These are **Claude Code** skills, invoked via the `Skill` tool. ZeroClaw has its
own separate feature also called "skills" (`SKILL.md`/`SKILL.toml` installed into
an agent's bundle). `zeroclaw-skills-tools` is a Claude Code skill *about* that
ZeroClaw feature. The two are not interchangeable.

## Skills

| Skill | Use it for |
|---|---|
| `zeroclaw-orientation` | What ZeroClaw is, the config model, the alias graph. Start here. |
| `zeroclaw-introspect` | Inspecting a running instance: status, health, config, cost, logs. |
| `zeroclaw-agents` | Creating, wiring, renaming, and deleting agents. |
| `zeroclaw-mcp` | Granting MCP servers to agents via config bundles. |
| `zeroclaw-skills-tools` | Installing and auditing ZeroClaw's own skills; tool visibility. |

## Install

```sh
./install.sh            # symlink skills/* into ~/.claude/skills/
./install.sh --dry-run  # show what would happen
./install.sh --force    # replace stale symlinks
```

`install.sh` never overwrites a real directory — only symlinks it owns.
Set `CLAUDE_SKILLS_DIR` to install somewhere other than `~/.claude/skills`.

## Compatibility

Verified against **ZeroClaw v0.8.3**. See [COMPATIBILITY.md](./COMPATIBILITY.md).

## Development

```sh
./validate.sh   # structural checks on every skill
```
```

Create `~/prj/zeroclaw-admin-skills/COMPATIBILITY.md`:

```markdown
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
```

- [ ] **Step 7: Run the validator and confirm the expected failures**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: five `FAIL: <name>: directory missing` lines, `exit=1`. Scaffolding does not create skills, so this must still fail.

- [ ] **Step 8: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add .gitignore LICENSE README.md COMPATIBILITY.md install.sh validate.sh
git commit -m "feat: repo scaffolding, symlink installer, and validation harness

install.sh links skills/* into ~/.claude/skills/ idempotently and refuses
to clobber non-symlink entries. validate.sh enforces frontmatter, name/dir
agreement, the v0.8.3 version pin, and eval well-formedness."
```

---

### Task 2: `zeroclaw-orientation`

**Files:**
- Create: `skills/zeroclaw-orientation/SKILL.md`
- Create: `skills/zeroclaw-orientation/references/config-model.md`
- Create: `skills/zeroclaw-orientation/evals/evals.json`

**Interfaces:**
- Consumes: `validate.sh` from Task 1.
- Produces: the canonical concepts the other four skills link to. Later skills reference it with the exact phrase `see the `zeroclaw-orientation` skill` and MUST NOT restate the alias grammar or the agent-as-a-join model.

- [ ] **Step 1: Verify the alias grammar before writing it down**

Run:

```bash
grep -n "fn validate_alias_key" -A 45 \
  /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083/crates/zeroclaw-config/src/helpers.rs
```

Expected: confirms lowercase `a-z`/`0-9`/`_` only, must start and end alphanumeric, rejects `__`, max 63 chars, explicitly rejects hyphen and uppercase.

- [ ] **Step 2: Write `SKILL.md`**

Create `skills/zeroclaw-orientation/SKILL.md`:

```markdown
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
```

- [ ] **Step 3: Write `references/config-model.md`**

Create `skills/zeroclaw-orientation/references/config-model.md`:

```markdown
# The config model and security posture

Verified against ZeroClaw v0.8.3.

## Top-level config sections

| Section | Holds |
|---|---|
| `[agents.<alias>]` | The join: references plus owned filesystem components |
| `[providers.models.<family>.<alias>]` | LLM endpoints. Also `providers.tts.*`, `providers.transcription.*` |
| `[channels.<type>.<alias>]` | Chat/transport adapters |
| `[risk_profiles.<alias>]` | Autonomy and sandbox posture |
| `[runtime_profiles.<alias>]` | Operational tuning: iteration caps, budgets, timeouts, delegation |
| `[peer_groups.<name>]` | Opt-in cross-agent messaging sets |
| `[skill_bundles.<alias>]` | Named directories of ZeroClaw skills |
| `[mcp]` / `[mcp_bundles.<alias>]` | MCP servers and the bundles that grant them |
| `[gateway]` | Bind host/port, pairing, remote admin |
| `[security]` | OTP gating, estop, leak detection |

## Risk profiles versus runtime profiles

They are deliberately separate and an agent references one of each.

- **Risk profile** (`[risk_profiles.<alias>]`) governs *authority*. Its `level`
  is `readonly`, `supervised` (default), or `full`. It also carries
  `workspace_only`, `forbidden_paths`, `allowed_commands`, `forbidden_commands`,
  sandbox settings, per-tool `auto_approve` / `always_ask` / `excluded_tools`
  lists, and `delegation_policy`.
- **Runtime profile** (`[runtime_profiles.<alias>]`) governs *operation*:
  agentic mode, tool-iteration caps, action and cost budgets, timeouts, context
  limits.

`readonly`, `supervised`, and `full` are the only accepted level values.
`read_only` with an underscore is **rejected at config load**.

## What the three autonomy levels do

- **`readonly`** — observation only. Permitted: `file_read`, `file_list`,
  `memory_search`, `http` (GET only), `web_search`, `time`.
- **`supervised`** (default) — low-risk tools run; medium-risk prompt the
  operator through the originating channel; high-risk are blocked.
- **`full`** — no approval gates. `workspace_only` is implicitly disabled.
  `forbidden_paths` and the OS sandbox still enforce.

## The six enforcement layers

Outermost to innermost: channel pairing and allow-lists → autonomy level →
workspace boundary and `forbidden_paths` → shell command policy
(`allowed_commands`, `forbidden_commands`, destructive-pattern validation) →
OS-level sandbox (Landlock/Bubblewrap/Firejail on Linux, Seatbelt on macOS,
AppContainer on Windows, Docker anywhere) → tool receipts (HMAC evidence on
successful tool results; ephemeral keys, not a durable audit log).

Additional gates: OTP on listed actions, `zeroclaw estop`, a prompt-injection
guard, an outbound leak detector, and device pairing.

Default posture out of the box: autonomy `supervised`, `workspace_only = true`,
sandbox auto-detected, audit logging **off**, OTP off, estop off.

## Secrets

Fields marked `#[secret]` in the schema are encrypted on disk with `.secret_key`
and are **never readable back**:

- `zeroclaw config get <secret-path>` reports population, not the value.
- `GET /api/config/prop` returns `{path, populated}` with no value, length, mask,
  or hash.
- `GET /api/config` returns the whole config with secrets replaced by masked
  placeholders.

To check whether a secret is set, use `zeroclaw config list --secrets`. It
reports which secret fields are populated. There is no supported path that
returns a secret's value.

Environment overrides (`ZEROCLAW_<path>` with `__` for dots) are applied to the
in-memory config at load and are **never persisted**. Saving masks them back to
the on-disk value so a temporary override cannot overwrite a real stored
credential.

## Stable config error codes

| Code | Meaning |
|---|---|
| `path_not_found` | The property does not exist in the schema |
| `validation_failed` | The whole-config validator rejected the proposed state |
| `dangling_reference` | An alias reference names a target that does not exist |
| `value_type_mismatch` | The value cannot coerce into the target type |
| `op_not_supported` | JSON Patch `move`/`copy`/unknown |
| `secret_test_forbidden` | JSON Patch `test` targeted a secret path |
| `config_changed_externally` | On-disk config drifted from the in-memory copy |
| `reload_failed` | Save succeeded but the daemon could not adopt it; on-disk reverted |
```

- [ ] **Step 4: Write `evals/evals.json`**

Create `skills/zeroclaw-orientation/evals/evals.json`:

```json
{
  "skill": "zeroclaw-orientation",
  "should_trigger": [
    "what is zeroclaw?",
    "explain how zeroclaw's config model works",
    "how do agents relate to providers and channels in zeroclaw?",
    "what are the rules for a zeroclaw alias?",
    "where does zeroclaw store its config and state?",
    "what's the difference between a risk profile and a runtime profile?"
  ],
  "should_not_trigger": [
    "what's my zeroclaw agent's current status?",
    "is my zeroclaw daemon healthy right now?",
    "create a new zeroclaw agent called example_agent",
    "add an MCP server to my agent",
    "install a skill into my zeroclaw bundle"
  ]
}
```

- [ ] **Step 5: Run the validator**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: four remaining `FAIL: <name>: directory missing` lines (for introspect, agents, mcp, skills-tools) and **no** failures mentioning `zeroclaw-orientation`. `exit=1`.

- [ ] **Step 6: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add skills/zeroclaw-orientation
git commit -m "feat(orientation): concepts hub for the ZeroClaw skill family

Agent-as-a-join model, alias grammar (including the two-namespace hyphen
trap), install layout, and the saved-is-not-applied rule. Security model
and config error codes in references/config-model.md."
```

---

### Task 3: `zeroclaw-introspect`

**Files:**
- Create: `skills/zeroclaw-introspect/SKILL.md`
- Create: `skills/zeroclaw-introspect/references/gateway-endpoints.md`
- Create: `skills/zeroclaw-introspect/evals/evals.json`

**Interfaces:**
- Consumes: `zeroclaw-orientation` (linked, not restated).
- Produces: the discovery preamble (locate binary, resolve config dir, find agent aliases) that `zeroclaw-agents`, `zeroclaw-mcp`, and `zeroclaw-skills-tools` all reference by name rather than duplicating.

- [ ] **Step 1: Verify the introspection command surface**

Run:

```bash
cd /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083
grep -n "enum ConfigCommands" -A 100 src/main.rs | grep -E "Schema|List|Get|Set|Init|Migrate|Patch|Docs|Generate"
grep -n "enum SecurityCommands" -A 15 src/main.rs
grep -oE '\.route\("(/health|/metrics|/api/(status|health|cost|tools|logs|sessions))"' crates/zeroclaw-gateway/src/lib.rs | sort -u
```

Expected: `ConfigCommands` contains `Schema`, `List`, `Get`, `Set`, `Init`, `Migrate`, `Patch`, `Docs`, `Generate`; `SecurityCommands` contains `Status { agent, json }`; the routes `/health`, `/metrics`, `/api/status`, `/api/health`, `/api/cost`, `/api/tools`, `/api/logs`, `/api/sessions` all exist.

- [ ] **Step 2: Write `SKILL.md`**

Create `skills/zeroclaw-introspect/SKILL.md`:

```markdown
---
name: zeroclaw-introspect
description: Interrogates a running ZeroClaw instance for runtime state and its own configuration - status, component health, effective security posture, config values, cost, sessions, and logs. Use when asked what an agent is doing, whether the daemon is healthy, what a config value is set to, why a channel is failing, or to troubleshoot a ZeroClaw instance. Read-only; use zeroclaw-agents or zeroclaw-mcp to change anything.
---

# Interrogating a ZeroClaw instance

Verified against **ZeroClaw v0.8.3**. Assumes the session runs on the same host
as the daemon.

This skill is **read-only**. It never mutates config. For concepts, see the
`zeroclaw-orientation` skill.

## Discovery first

Establish these before running anything else, and reuse the answers for the rest
of the conversation.

**1. Find the binary.** In order: `command -v zeroclaw`, then
`./target/release/zeroclaw` or `./target/debug/zeroclaw` if working inside a
ZeroClaw source tree, then `~/.cargo/bin/zeroclaw`.

```sh
command -v zeroclaw || ls ~/.cargo/bin/zeroclaw ./target/release/zeroclaw 2>/dev/null
```

**2. Resolve the config directory and confirm the instance exists.**

```sh
zeroclaw status
```

The output reports the config file path it actually resolved against — this is
the authoritative answer, not an assumption about `~/.zeroclaw/`. It also reports
provider, model, uptime, channels, and memory backend.

**3. Discover agent aliases.** Every agent-scoped command needs one; there is no
default agent.

```sh
zeroclaw agents list
```

If more than one exists, ask which to target rather than guessing.

**4. Check whether the daemon is actually running.** Many endpoints only answer
when it is.

```sh
curl -sf http://localhost:42617/health >/dev/null && echo "daemon up" || echo "daemon down"
```

## Runtime state

**Overall health, including per-component status:**

```sh
curl -s http://localhost:42617/health | jq
```

Each entry in `runtime.components` carries `status` (`starting`/`ok`/`error`),
`updated_at`, `last_ok`, `last_error`, and `restart_count`. The two things worth
looking for are `status: "error"` and a climbing `restart_count`.

**Diagnostics, including provider connectivity:**

```sh
zeroclaw doctor
```

**Effective security posture for one agent** — this resolves the agent's risk
profile into what it can actually do, rather than showing the raw config:

```sh
zeroclaw security status --agent <alias>
zeroclaw security status --agent <alias> --json
```

Use this whenever the question is "why won't this agent run a tool" or "how
locked down is this agent."

**Cost and token spend:**

```sh
curl -s http://localhost:42617/api/cost | jq
```

**Tools currently registered**, with descriptions and parameter schemas:

```sh
curl -s http://localhost:42617/api/tools | jq
```

**Sessions:**

```sh
curl -s http://localhost:42617/api/sessions | jq
```

**Prometheus metrics** — requires `[observability] backend = "prometheus"`;
without it the endpoint returns a one-line hint instead of metrics:

```sh
curl -s http://localhost:42617/metrics
```

Useful series: `zeroclaw_tool_calls_total{tool,success}`,
`zeroclaw_llm_requests_total`, `zeroclaw_errors_total`, `zeroclaw_active_sessions`,
`zeroclaw_tokens_input_total`, `zeroclaw_tokens_output_total`.

## Configuration

**List values under a prefix:**

```sh
zeroclaw config list --filter agents
zeroclaw config list --filter mcp
```

**Read one value:**

```sh
zeroclaw config get agents.<alias>.model_provider
zeroclaw config get agents.<alias>.model_provider --json
```

**Ask the config to describe itself.** This returns the JSON Schema fragment for
a path — types, enums, defaults, constraints — without needing the gateway:

```sh
zeroclaw config schema --path agents
zeroclaw config schema --path mcp.servers
```

Use this instead of guessing a field name or its accepted values.

**Check which secrets are populated:**

```sh
zeroclaw config list --secrets
```

> **Secrets are never readable.** Reads report population only — no value, no
> length, no mask, no hash. If asked to show an API key, explain that no
> supported path returns one, and report whether it is populated instead.

## Logs

```sh
# Linux, user service
journalctl --user -u zeroclaw -f
journalctl --user -u zeroclaw --since "1 hour ago"

# macOS and Windows write files instead
tail -f ~/.zeroclaw/logs/daemon.stderr.log
```

Over the gateway: `curl -s http://localhost:42617/api/logs | jq`

## Live event stream

```sh
curl -N http://localhost:42617/api/events
```

Server-Sent Events. Treat it as an append-only observation log, **not** a
deduplicated one-row-per-turn timeline — gateway handlers, cron, and agent-loop
observers all publish into the same broadcast path, so a given `agent_start` or
`llm_request` may appear more than once. Group by the identifiers on the payload
if a compact timeline is needed. `/api/events/history` replays the retained
buffer, oldest first.

## Troubleshooting map

| Symptom | First move |
|---|---|
| `command not found` | Binary not on PATH; check `~/.cargo/bin` and `./target/release` |
| Connection refused on curl | Daemon not running — `zeroclaw daemon`, or `zeroclaw service status` |
| `401`/`403` from the gateway | Pairing required; loopback admin calls need no token but API calls may |
| Agent won't use a tool | `zeroclaw security status --agent <alias>` — check level and `excluded_tools` |
| Config change had no effect | Saved is not applied — see "Applying changes" below |
| Channel in `error` state | `/health` `last_error`, then `zeroclaw channels list` |
| Memory not persisting | `zeroclaw config get memory.backend` — `none` stores nothing |
| Daemon restarting repeatedly | `journalctl --user -u zeroclaw`, then set `RUST_LOG=debug` in the unit |

## Applying changes

If inspection reveals the on-disk config disagrees with running behavior, the
daemon has not reloaded. Trigger it:

```sh
curl -X POST http://localhost:42617/admin/reload
```

Loopback callers need no token. Then re-run the check that showed the
discrepancy. If the daemon was started as `zeroclaw gateway` rather than
`zeroclaw daemon`, reload returns a restart-required response because there is
no supervising daemon loop.

For the full endpoint inventory, read `references/gateway-endpoints.md`.
```

- [ ] **Step 3: Write `references/gateway-endpoints.md`**

Create `skills/zeroclaw-introspect/references/gateway-endpoints.md`:

```markdown
# Gateway endpoints (v0.8.3)

Default bind: `localhost:42617`. Routes verified against
`crates/zeroclaw-gateway/src/lib.rs` at tag v0.8.3.

## Read-only

| Endpoint | Returns |
|---|---|
| `GET /health` | Public. Status, pairing state, runtime component map |
| `GET /api/health` | Authenticated equivalent |
| `GET /api/status` | Same information as `zeroclaw status`, as JSON |
| `GET /api/cost` | Session/daily/monthly cost, token counts, per-model breakdown |
| `GET /metrics` | Prometheus text exposition; needs `[observability] backend = "prometheus"` |
| `GET /api/tools` | Registered tools with descriptions and parameter schemas |
| `GET /api/sessions` | Active sessions; `/api/sessions/running` for running only |
| `GET /api/logs` | Recent log lines |
| `GET /api/channels` | Configured channels |
| `GET /api/events` | SSE stream; `/api/events/history` replays the buffer |
| `GET /api/memory` | Memory entries; `?query=` and `?category=` filter |
| `GET /api/cron` | Scheduled jobs |
| `GET /api/skills/bundles` | Configured skill bundles |
| `GET /api/docs` | Scalar API explorer; `/api/openapi.json` for the raw spec |

## Config

| Endpoint | Purpose |
|---|---|
| `GET /api/config` | Whole-config snapshot, secrets masked. Compatibility surface |
| `OPTIONS /api/config` | Whole-config JSON Schema. Capabilities, not values |
| `GET /api/config/prop?path=<dotted>` | One field. Secrets return `{path, populated}` only |
| `PUT /api/config/prop` | Write one field: `{path, value, comment?}` |
| `DELETE /api/config/prop?path=<dotted>` | Reset one field to default |
| `OPTIONS /api/config/prop?path=<dotted>` | Per-field schema fragment |
| `GET /api/config/list?prefix=<dotted>` | Enumerate reachable paths with type and category |
| `PATCH /api/config` | Atomic RFC 6902 JSON Patch. `add`/`replace`/`remove`/`test` only |
| `GET /api/config/drift` | Whether on-disk config drifted from the in-memory copy |
| `POST /api/config/migrate` | Apply schema migration in place |

`OPTIONS` returns capabilities; `GET` returns current values. The `Allow` header
on `OPTIONS /api/config` still advertises legacy `PUT`, which the router does not
register — ignore it.

## Admin

| Endpoint | Access |
|---|---|
| `POST /admin/reload` | Loopback always allowed, no token. Remote requires `gateway.allow_remote_admin = true` **and** pairing enabled |
| `POST /admin/shutdown` | Localhost only, regardless of `allow_remote_admin` |
| `GET /admin/paircode` | Localhost only |

`allow_remote_admin` has no effect unless `require_pairing` is also on: with
pairing disabled a remote caller cannot be authenticated, so the request is
rejected rather than allowed anonymously.

## The route inventory caveat

The OpenAPI document at `/api/openapi.json` is assembled separately from the
router and does not cover every registered route. The router in
`crates/zeroclaw-gateway/src/lib.rs` is the authority for what actually exists.
```

- [ ] **Step 4: Write `evals/evals.json`**

Create `skills/zeroclaw-introspect/evals/evals.json`:

```json
{
  "skill": "zeroclaw-introspect",
  "should_trigger": [
    "what's my zeroclaw agent's current status?",
    "is the zeroclaw daemon healthy?",
    "show me what model provider my agent is configured with",
    "how much have I spent on tokens this month?",
    "why is my telegram channel erroring in zeroclaw?",
    "what tools does my zeroclaw agent have available?",
    "check the effective security posture of my agent"
  ],
  "should_not_trigger": [
    "what is zeroclaw?",
    "explain the agent-as-a-join model",
    "create a new agent called example_agent",
    "grant the filesystem MCP server to my agent",
    "install the code-review skill into my ops bundle"
  ]
}
```

- [ ] **Step 5: Run the validator**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: three remaining `directory missing` failures (agents, mcp, skills-tools), none mentioning `zeroclaw-orientation` or `zeroclaw-introspect`. `exit=1`.

- [ ] **Step 6: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add skills/zeroclaw-introspect
git commit -m "feat(introspect): read-only interrogation of a running instance

Discovery preamble, health/component map, security status --agent for
effective posture, config self-description via config schema --path,
cost, logs, and a troubleshooting map. Endpoint inventory in references/."
```

---

### Task 4: `zeroclaw-agents`

**Files:**
- Create: `skills/zeroclaw-agents/SKILL.md`
- Create: `skills/zeroclaw-agents/references/wiring-order.md`
- Create: `skills/zeroclaw-agents/evals/evals.json`

**Interfaces:**
- Consumes: `zeroclaw-orientation` (alias grammar, join model), `zeroclaw-introspect` (discovery preamble).
- Produces: the four-beat mutation loop (read → dry-run → apply → reload and verify) that `zeroclaw-mcp` and `zeroclaw-skills-tools` reuse by name.

- [ ] **Step 1: Verify the agent/provider/channel CRUD surface**

Run:

```bash
grep -n "enum AgentsCommands" -A 28 \
  /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083/src/lib.rs
```

Expected: `List`, `Create { alias }`, `Rename { from, to }`, `Delete { alias, dry_run, yes }`. Confirm `Delete` carries both `--dry-run` and `--yes` before documenting them.

- [ ] **Step 2: Write `SKILL.md`**

Create `skills/zeroclaw-agents/SKILL.md`:

```markdown
---
name: zeroclaw-agents
description: Creates, wires, renames, and deletes ZeroClaw agents and the provider, channel, and profile aliases they reference. Use when asked to add a new agent, point an agent at a model provider or channel, change an agent's risk or runtime profile, rename or remove an agent, or fix a dangling_reference error. Covers agent lifecycle; use zeroclaw-mcp for MCP grants and zeroclaw-skills-tools for skills.
---

# Managing ZeroClaw agents

Verified against **ZeroClaw v0.8.3**. Assumes the session runs on the same host
as the daemon.

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

To discover the exact field names and accepted values rather than guessing:

```sh
zeroclaw config schema --path agents
```

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
```

- [ ] **Step 3: Write `references/wiring-order.md`**

Create `skills/zeroclaw-agents/references/wiring-order.md`:

```markdown
# Reference wiring order and CRUD surfaces

Verified against ZeroClaw v0.8.3.

## Safe creation order

Build from the leaves inward. Each step's targets must exist before the next
step points at them.

1. **Model provider** — `zeroclaw providers create models <family> <alias>`,
   then set `api_key` and `model`.
2. **Risk profile** — `[risk_profiles.<alias>]`. Created via `zeroclaw config set
   risk_profiles.<alias>.level supervised` (writing a field instantiates the
   section) or `zeroclaw config init risk_profiles`.
3. **Runtime profile** — `[runtime_profiles.<alias>]`, same pattern.
4. **Channels** — `zeroclaw channels create <type> <alias>`, then set the
   channel's credentials.
5. **Agent** — `zeroclaw agents create <alias>`.
6. **Wire the agent** — set `model_provider`, `risk_profile`, `runtime_profile`,
   and channel bindings.
7. **Reload** — `curl -X POST http://localhost:42617/admin/reload`.
8. **Verify** — `zeroclaw security status --agent <alias>` and a live
   `zeroclaw agent -a <alias> -m "hello"`.

Deleting runs in reverse: delete the agent first (its cascade scrubs its own
references), then the targets it pointed at.

## CRUD surfaces

All three share the same shape. Verified against `enum AgentsCommands`,
`enum ProvidersCommands`, and `enum ChannelsCommands` in `src/lib.rs`.

| Command | Signature |
|---|---|
| `zeroclaw agents list` | — |
| `zeroclaw agents create` | `<alias>` |
| `zeroclaw agents rename` | `<from> <to>` |
| `zeroclaw agents delete` | `<alias> [--dry-run] [--yes]` |
| `zeroclaw providers list` | `[--category <models\|tts\|transcription>]` |
| `zeroclaw providers create` | `<category> <family> <alias>` |
| `zeroclaw providers rename` | `<category> <family> <from> <to>` |
| `zeroclaw providers delete` | `<category> <family> <alias> [--dry-run] [--yes]` |
| `zeroclaw channels list` | `[--channel-type <type>]` |
| `zeroclaw channels create` | `<channel_type> <alias>` |
| `zeroclaw channels rename` | `<channel_type> <from> <to>` |
| `zeroclaw channels delete` | `<channel_type> <alias> [--dry-run] [--yes]` |

## Discovering fields instead of guessing

`zeroclaw config schema --path <dotted>` returns the JSON Schema fragment for any
path — field names, types, enums, defaults. Use it before writing a `config set`
for a field whose name is not already confirmed:

```sh
zeroclaw config schema --path agents
zeroclaw config schema --path risk_profiles
zeroclaw config schema --path runtime_profiles
```

## Batch changes

For several related edits that must land together, use a JSON Patch document.
It applies atomically: every operation runs against an in-memory copy, the whole
config is validated once, and nothing is persisted if any operation or the final
validation fails.

```sh
cat <<'EOF' | zeroclaw config patch -
[
  {"op": "replace", "path": "/agents/example_agent/model_provider", "value": "anthropic.prod"},
  {"op": "replace", "path": "/agents/example_agent/risk_profile", "value": "hardened"}
]
EOF
```

Both JSON Pointer (`/agents/example_agent/...`) and dotted
(`agents.example_agent....`) path forms are accepted. Supported operations are
`add`, `replace`, `remove`, and `test`. `move` and `copy` are rejected with
`op_not_supported`. A `test` against a secret path is rejected with
`secret_test_forbidden`, because a differential outcome would leak the value.
```

- [ ] **Step 4: Write `evals/evals.json`**

Create `skills/zeroclaw-agents/evals/evals.json`:

```json
{
  "skill": "zeroclaw-agents",
  "should_trigger": [
    "create a new zeroclaw agent called example_agent",
    "point my agent at the anthropic provider",
    "rename my zeroclaw agent from bot to assistant",
    "delete the old test agent",
    "I'm getting a dangling_reference error when loading config",
    "change my agent's autonomy level to full",
    "add a new telegram channel alias"
  ],
  "should_not_trigger": [
    "what is zeroclaw?",
    "what's my agent's current status?",
    "add an MCP server for filesystem access",
    "install a skill from a git repo",
    "how much have I spent on tokens?"
  ]
}
```

- [ ] **Step 5: Run the validator**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: two remaining `directory missing` failures (mcp, skills-tools). `exit=1`.

- [ ] **Step 6: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add skills/zeroclaw-agents
git commit -m "feat(agents): agent lifecycle and reference wiring

Disambiguates 'agents' from 'agent', establishes the read/dry-run/apply/
reload loop, documents creation order against dangling_reference, and
requires dry-run plus explicit confirmation before cascading deletes."
```

---

### Task 5: `zeroclaw-mcp`

**Files:**
- Create: `skills/zeroclaw-mcp/SKILL.md`
- Create: `skills/zeroclaw-mcp/references/server-config.md`
- Create: `skills/zeroclaw-mcp/evals/evals.json`

**Interfaces:**
- Consumes: `zeroclaw-orientation` (alias grammar), `zeroclaw-agents` (the four-beat mutation loop).
- Produces: nothing consumed downstream.

- [ ] **Step 1: Verify the MCP schema before writing it down**

Run:

```bash
cd /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083
grep -n "pub struct McpServerConfig" -A 45 crates/zeroclaw-config/src/schema.rs
grep -n "pub struct McpBundleConfig" -A 12 crates/zeroclaw-config/src/schema.rs
grep -n "fn mcp_servers_for_bundles" -A 35 crates/zeroclaw-config/src/schema.rs
grep -rn "Mcp {" src/main.rs || echo "CONFIRMED: no top-level mcp subcommand"
```

Expected: `env` and `headers` each carry `#[secret]`; `args` does not. `McpBundleConfig` has `servers` and `exclude`. `mcp_servers_for_bundles` drops any name appearing in an `exclude` list. The last command prints the confirmation line.

- [ ] **Step 2: Write `SKILL.md`**

Create `skills/zeroclaw-mcp/SKILL.md`:

```markdown
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

**Step 1 — define the server.** For a stdio server:

```sh
zeroclaw config set mcp.servers.filesystem.transport stdio
zeroclaw config set mcp.servers.filesystem.command /usr/local/bin/mcp-server-filesystem
zeroclaw config set mcp.servers.filesystem.args '["--root","/srv/data"]'
```

Confirm the exact field names and accepted transport values rather than guessing:

```sh
zeroclaw config schema --path mcp.servers
```

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
curl -s http://localhost:42617/api/tools | jq '.[] | select(.name | startswith("filesystem__"))'
```

MCP tools are namespaced `<server>__<tool>`, so the server name becomes a tool
prefix. Seeing the prefixed tools in `/api/tools` is the proof the grant worked.

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
curl -X POST http://localhost:42617/admin/reload     # 5. reloaded since the change?
curl -s http://localhost:42617/api/tools | jq        # 6. tools visible now?
zeroclaw security status --agent <alias>             # 7. policy excluding them?
```

Also check `deferred_loading`: when `mcp.deferred_loading` is true, only tool
names are listed in the system prompt and the model must call `tool_search` to
fetch full schemas before invoking a tool. Tools exist but look absent in the
prompt — this is expected, not a fault.

For the full field inventory and transport-specific requirements, read
`references/server-config.md`.
```

- [ ] **Step 3: Write `references/server-config.md`**

Create `skills/zeroclaw-mcp/references/server-config.md`:

```markdown
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

Resolution, per `Config::mcp_servers_for_bundles`: the union of `servers` across
every bundle the agent references, minus the union of every `exclude`. A server
name with no matching `[mcp.servers]` entry grants nothing.

## Agent fields

| Field | Type | Meaning |
|---|---|---|
| `mcp_bundles` | list of strings | Bundle aliases this agent receives. Empty means **no MCP servers** |
| `acp_enable_mcp` | bool | Initialize this agent's MCP tools when it serves an ACP session |

`Config::mcp_servers_for_agent` returns an empty list for an unknown alias or one
with no `mcp_bundles`. Default-deny is the designed behavior, not a bug.

## Setting list and map values from the CLI

List-valued fields take a JSON array; map-valued fields are addressed per key:

```sh
zeroclaw config set mcp_bundles.research.servers '["filesystem","github"]'
zeroclaw config set mcp.servers.github.env.GITHUB_TOKEN
```

Omitting the value on a secret field triggers a masked interactive prompt. Use
`--no-interactive` in scripts, which requires the value on the command line.
```

- [ ] **Step 4: Write `evals/evals.json`**

Create `skills/zeroclaw-mcp/evals/evals.json`:

```json
{
  "skill": "zeroclaw-mcp",
  "should_trigger": [
    "add an MCP server to zeroclaw",
    "give my example_agent agent access to the filesystem MCP",
    "why can't my agent see the MCP tools?",
    "revoke the github MCP server from this agent",
    "how do I store the MCP bearer token securely?",
    "set up an mcp bundle for my agent"
  ],
  "should_not_trigger": [
    "what is zeroclaw?",
    "create a new agent called example_agent",
    "install a zeroclaw skill from a git repo",
    "what's my daemon's health status?",
    "how much have I spent on tokens?"
  ]
}
```

- [ ] **Step 5: Run the validator**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: one remaining `FAIL: zeroclaw-skills-tools: directory missing`. `exit=1`.

- [ ] **Step 6: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add skills/zeroclaw-mcp
git commit -m "feat(mcp): config-only MCP provisioning with default-deny framing

Documents the three-level grant chain, the deny-wins exclude semantics,
credentials in env/headers rather than plaintext args, and pinned_resources
as a prompt-injection surface. Notes that no mcp subcommand exists at v0.8.3."
```

---

### Task 6: `zeroclaw-skills-tools`

**Files:**
- Create: `skills/zeroclaw-skills-tools/SKILL.md`
- Create: `skills/zeroclaw-skills-tools/references/skill-authoring.md`
- Create: `skills/zeroclaw-skills-tools/evals/evals.json`

**Interfaces:**
- Consumes: `zeroclaw-orientation` (alias grammar and the two-namespace rule), `zeroclaw-agents` (mutation loop).
- Produces: nothing consumed downstream.

- [ ] **Step 1: Verify the skills CLI surface**

Run:

```bash
cd /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083
grep -n "enum SkillCommands" -A 110 src/lib.rs
grep -n "enum SkillBundleCommands" -A 48 src/lib.rs
```

Expected: `SkillCommands` = `List`, `Add`, `Edit`, `Bundle`, `Audit`, `Install`, `Remove`, `Test`. **Confirm `Install` has only `agent`, `bundle`, `no_tier_banner` — no `skill` field.** `SkillBundleCommands` = `List`, `Add`, `Remove`, `Rename`, `Show`.

- [ ] **Step 2: Write `SKILL.md`**

Create `skills/zeroclaw-skills-tools/SKILL.md`:

```markdown
---
name: zeroclaw-skills-tools
description: Installs, audits, and manages ZeroClaw's own skills and skill bundles, and diagnoses which tools an agent actually loads at runtime. Use when asked to install a ZeroClaw skill, create or manage a skill bundle, audit a skill before trusting it, or work out why an installed skill is not being used by an agent. This is about ZeroClaw's skill feature, not Claude Code skills.
---

# ZeroClaw skills and tool visibility

Verified against **ZeroClaw v0.8.3**. Assumes the session runs on the same host
as the daemon.

> **Scope note.** This covers **ZeroClaw's** skill feature — `SKILL.md`/`SKILL.toml`
> files installed into a ZeroClaw bundle and loaded by a ZeroClaw agent at runtime.
> It is not about Claude Code skills, even though both use the name and the
> `SKILL.md` filename.

Uses the four-beat mutation loop from `zeroclaw-agents`. For alias rules see
`zeroclaw-orientation`.

## Two namespaces with opposite rules

- **Bundle aliases** are config aliases: lowercase, digits, single underscores.
  **No hyphens.** `zeroclaw skills bundle add --help` claims "lowercase +
  hyphens"; that help text is wrong — the alias is validated by
  `validate_alias_key`, which rejects hyphens.
- **Skill names** are directory names: lowercase **with hyphens**, e.g.
  `code-review`.

So: bundle `ops_tools`, skill `release-check`.

## Where skills live

```text
<install>/agents/<alias>/workspace/skills/<name>/   per-agent workspace skills
<install>/shared/skills/<bundle>/<name>/            bundle skills — loaded via config
<install>/data/skills/<name>/                       global — NOT auto-loaded by any agent
```

Only bundle skills are loaded at runtime through config. **The global directory is
a trap**: `zeroclaw skills install` falls back to it when it cannot determine a
bundle, the skill installs successfully and appears in `zeroclaw skills list`, and
no agent ever loads it.

## The workflow

**Step 1 — create a bundle** (directory defaults to `<install>/shared/skills/<alias>/`):

```sh
zeroclaw skills bundle add ops_tools
zeroclaw skills bundle list
```

**Step 2 — attach the bundle to the agent:**

```sh
zeroclaw config set agents.<alias>.skill_bundles '["ops_tools"]'
```

**Step 3 — audit before installing.** Always audit a source you did not write:

```sh
zeroclaw skills audit ./release-check
```

**Step 4 — install into the bundle explicitly.** Pass `--bundle` so the
destination is never ambiguous:

```sh
zeroclaw skills install ./release-check --bundle ops_tools
zeroclaw skills install https://example.com/zeroclaw-release-check.git --bundle ops_tools
```

Destination precedence: explicit `--bundle`, then the target agent's single
assigned bundle (`--agent` selects the agent), then the global directory. If the
agent has multiple bundles, `--bundle` is required to disambiguate.

> `skills install` at v0.8.3 has **no `--skill` flag**. Some documentation shows
> `--skill <name>` for installing one skill from a catalog repository; that flag
> does not exist in this version.

**Step 5 — verify what the agent actually loads.** This is the check that
matters, and it differs from the full inventory:

```sh
zeroclaw skills list                      # everything installed
zeroclaw skills list --bundle ops_tools   # one bundle
zeroclaw skills list --agent <alias>      # what this agent loads at runtime
```

**Step 6 — reload:**

```sh
curl -X POST http://localhost:42617/admin/reload
```

## Authoring a skill in place

```sh
zeroclaw skills add release-check \
  --bundle ops_tools \
  --description "Check release readiness before tagging" \
  --edit
```

Writes `<bundle-directory>/release-check/SKILL.md` plus the canonical subdirs
(`scripts/`, `references/`, `assets/`) unless `--no-scaffold` is passed. The
description is required and is prompted for on a TTY when omitted. Other options:
`--license`, `--author`, `--version`, `--category`.

To edit an existing skill or a sibling file:

```sh
zeroclaw skills edit release-check --bundle ops_tools
zeroclaw skills edit release-check --file references/checklist.md
```

## Script safety — leave it off

ZeroClaw audits skills before loading or installing them. Script-like files —
`.sh`, `.bash`, `.ps1`, and anything with a shell shebang — are **blocked by
default**.

`skills.allow_scripts` lifts that block. Keep it disabled unless the skill source
is trusted and the scripts have been read. If a user asks to enable it, say
plainly what it permits: arbitrary scripts from installed skills become
executable by the agent.

Related: `zeroclaw skills test <name>` runs the skill's `TEST.sh` when one
exists. Inspect `TEST.sh` before running it against a source you do not trust.

Community open-skills loading is also opt-in. When enabled, ZeroClaw loads from
`open_skills_dir` (default `$HOME/open-skills`) and may clone or pull the
community repository. Enable it only for sources trusted at that level, or point
it at a reviewed local copy.

## Removing — confirm first

Removing a skill from a bundle archives its directory so it can be recovered.
Removing a **bundle** archives the directory *and* strips it from every agent's
`skill_bundles` list — confirm before doing that.

```sh
zeroclaw skills remove release-check --bundle ops_tools
zeroclaw skills bundle remove ops_tools --yes   # confirm with the user first
```

## When an installed skill is not being used

```sh
zeroclaw skills list                       # 1. installed at all?
zeroclaw skills list --agent <alias>       # 2. does THIS agent load it?
zeroclaw config get agents.<alias>.skill_bundles   # 3. bundle attached?
zeroclaw skills bundle show <bundle>       # 4. skill actually in that bundle?
zeroclaw skills audit <name>               # 5. blocked by the script audit?
curl -X POST http://localhost:42617/admin/reload   # 6. reloaded since install?
```

If the skill appears in `skills list` but not in `skills list --agent`, it landed
in the global directory. Reinstall it with an explicit `--bundle`, and make sure
the agent references that bundle.

## Tool visibility generally

Skills are one source of agent capability; built-in tools and MCP servers are the
others. To see everything an agent can currently call:

```sh
curl -s http://localhost:42617/api/tools | jq '.[].name'
zeroclaw security status --agent <alias>
```

A tool can be present but unusable: the risk profile's `excluded_tools`, or a
channel's `excluded_tools`, hides it. A tool excluded at the channel level is
never advertised to the model on that channel. For MCP specifically, see the
`zeroclaw-mcp` skill.

For frontmatter fields, `SKILL.toml` structure, and slash-command options, read
`references/skill-authoring.md`.
```

- [ ] **Step 3: Write `references/skill-authoring.md`**

Create `skills/zeroclaw-skills-tools/references/skill-authoring.md`:

```markdown
# Authoring ZeroClaw skills (v0.8.3)

Two local authoring formats. Use `SKILL.md` for instructions plus simple
metadata; use `SKILL.toml` when the skill needs structured prompts or tool
definitions. `manifest.toml` is also understood for registry-style packages but
is not the recommended local format.

## `SKILL.md`

The directory name becomes the skill name. Without frontmatter, the first
non-heading paragraph is used as the description.

```markdown
---
name: release-check
description: Check release readiness before tagging
version: 0.1.0
author: zeroclaw_user
tags: [release, docs]
---

# Release check

Review the release notes, changelog, version tags, and migration notes before
confirming that a release is ready.
```

Supported frontmatter fields: `name`, `description`, `version`, `author`, `tags`.

## `SKILL.toml`

The `[skill]` table requires `name` and `description`. `version` defaults to
`0.1.0`. `author`, `tags`, and `prompts` are optional. Tool entries take
`kind = "shell"`, `kind = "http"`, or `kind = "script"`. Keep tool descriptions
narrow and concrete so the model knows when to use them.

A skill tagged `slash` is surfaced as a chat-channel slash command. It may
declare typed `[[skill.slash_options]]`; one that declares none falls back to a
single required free-text input. Command and option descriptions accept a
`description_localizations` map keyed by locale code; unknown locale codes are
dropped with a warning rather than failing registration.

```toml
[skill]
name = "search"
description = "Search the web"
tags = ["slash"]
description_localizations = { fr = "Rechercher sur le web" }

[[skill.slash_options]]
name = "query"
description = "The search query"
type = "string"
required = true
```

## CLI surface

Verified against `enum SkillCommands` and `enum SkillBundleCommands` in
`src/lib.rs`.

| Command | Signature |
|---|---|
| `zeroclaw skills list` | `[--agent <alias>] [--bundle <alias>]` |
| `zeroclaw skills add` | `<name> [--bundle] [--description] [--license] [--author] [--version] [--category] [--no-scaffold] [--edit]` |
| `zeroclaw skills edit` | `<name> [--bundle] [--file <relpath>]` |
| `zeroclaw skills audit` | `<source>` — path or installed name |
| `zeroclaw skills install` | `<source> [--agent] [--bundle] [--no-tier-banner]` |
| `zeroclaw skills remove` | `<name> [--agent] [--bundle]` |
| `zeroclaw skills test` | `[name] [--verbose]` |
| `zeroclaw skills bundle list` | — |
| `zeroclaw skills bundle add` | `<alias> [--directory <path>]` |
| `zeroclaw skills bundle remove` | `<alias> [--yes]` |
| `zeroclaw skills bundle rename` | `<from> <to>` |
| `zeroclaw skills bundle show` | `<alias>` |

`--bundle` takes precedence over `--agent` on `skills list`. A bundle's
`--directory` override must resolve inside `<install>/shared/`.

## Prompt injection mode

`skills.prompt_injection_mode` defaults to `full`, which puts complete skill
instructions in the system prompt. `compact` keeps only metadata in context and
loads details on demand — worth switching when many skills are loaded and context
is tight.

## Autonomous skill creation

Off by default. When `[skills.skill_creation] enabled = true`, ZeroClaw can
persist a completed multi-step execution (at least two tool calls) as a reusable
skill. By default this is a deterministic `SKILL.toml` generated from the
tool-call trace with no model call.

`reflection_enabled = true` instead asks the agent's provider to synthesize a
`SKILL.md` from a bounded slice of the execution. Each input is independently
truncated (`max_task_chars`, `max_tool_trace_chars`, `max_final_answer_chars`).
Because reflection forwards turn content to the provider, the task, trace, and
final answer are scanned for credential-shaped values and redacted in-process
before the request is composed. If reflection fails, it falls back to the
deterministic path.

`max_skills` sets an LRU cap; `similarity_threshold` sets the embedding-dedup
cutoff. `[skills.skill_improvement]` is a separate feature that patches existing
skills after use — the two are enabled independently.
```

- [ ] **Step 4: Write `evals/evals.json`**

Create `skills/zeroclaw-skills-tools/evals/evals.json`:

```json
{
  "skill": "zeroclaw-skills-tools",
  "should_trigger": [
    "install a zeroclaw skill from this directory",
    "create a skill bundle for my ops agent",
    "audit this skill before I install it",
    "my agent isn't using the skill I installed",
    "what tools does my zeroclaw agent actually load?",
    "should I enable allow_scripts for zeroclaw skills?"
  ],
  "should_not_trigger": [
    "what is zeroclaw?",
    "create a new zeroclaw agent",
    "add an MCP server to my agent",
    "is my daemon healthy?",
    "what's my token spend this month?"
  ]
}
```

- [ ] **Step 5: Run the validator — it must now pass**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: `OK: all 5 skills valid` and `exit=0`.

- [ ] **Step 6: Commit**

```bash
cd ~/prj/zeroclaw-admin-skills
git add skills/zeroclaw-skills-tools
git commit -m "feat(skills-tools): ZeroClaw skill and bundle management

Covers the bundle-alias vs skill-name namespace split, the global-directory
trap where an installed skill is never loaded, the default-on script audit,
and runtime tool visibility. Records that skills install has no --skill flag."
```

---

### Task 7: Integration verification and install

**Files:**
- Modify: `skills/<name>/SKILL.md` frontmatter `description` — only for skills Step 3 finds to be colliding. No edits if the descriptions are already disjoint.

**Interfaces:**
- Consumes: all five skills and both scripts.
- Produces: an installed, verified skill family.

- [ ] **Step 1: Confirm the validator passes cleanly**

Run: `cd ~/prj/zeroclaw-admin-skills && ./validate.sh; echo "exit=$?"`

Expected: `OK: all 5 skills valid`, `exit=0`.

- [ ] **Step 2: Confirm no skill restates what orientation owns**

The other four must link to `zeroclaw-orientation` rather than duplicating the
alias grammar.

```bash
cd ~/prj/zeroclaw-admin-skills
for s in zeroclaw-introspect zeroclaw-agents zeroclaw-mcp zeroclaw-skills-tools; do
  printf '%s: ' "$s"
  grep -c "zeroclaw-orientation" "skills/$s/SKILL.md"
done
```

Expected: each prints a count of 1 or more. A `0` means that skill orphaned its
concepts link — add one.

- [ ] **Step 3: Check trigger descriptions for collisions**

```bash
cd ~/prj/zeroclaw-admin-skills
for s in skills/*/SKILL.md; do
  printf '\n=== %s ===\n' "$(basename "$(dirname "$s")")"
  sed -n 's/^description:[[:space:]]*//p' "$s"
done
```

Read the five descriptions together. Each must name a distinct job. The pair to
scrutinise is `orientation` (concepts, no running instance) against `introspect`
(inspecting a running instance). If two descriptions could plausibly match the
same request, narrow the weaker one and re-run `./validate.sh`.

- [ ] **Step 4: Verify the forbidden-flag guard actually fires**

The validator must catch a regression that reintroduces the nonexistent flag.

```bash
cd ~/prj/zeroclaw-admin-skills
printf '\nzeroclaw skills install https://example.com/x.git --skill foo\n' \
  >> skills/zeroclaw-skills-tools/SKILL.md
./validate.sh; echo "exit=$?"
git checkout skills/zeroclaw-skills-tools/SKILL.md
./validate.sh; echo "exit=$?"
```

Expected: first run reports the `--skill` failure and `exit=1`; after the
checkout, `OK: all 5 skills valid` and `exit=0`.

- [ ] **Step 5: Dry-run the installer, then install**

```bash
cd ~/prj/zeroclaw-admin-skills
./install.sh --dry-run
./install.sh
ls -l ~/.claude/skills | grep zeroclaw-
```

Expected: the dry run lists five `linked` lines without creating anything; the
real run creates them; `ls -l` shows five symlinks pointing into
`~/prj/zeroclaw-admin-skills/skills/`.

If a real (non-symlink) directory already occupies one of those names,
`install.sh` refuses and exits non-zero. Report which name collided and let the
user decide; do not delete it.

- [ ] **Step 6: Confirm idempotency**

```bash
cd ~/prj/zeroclaw-admin-skills && ./install.sh; echo "exit=$?"
```

Expected: five `ok       <name> (already linked)` lines, `exit=0`.

- [ ] **Step 7: Commit any fixes and tag the verified state**

```bash
cd ~/prj/zeroclaw-admin-skills
git status --short
# If Step 3 required description edits, stage and commit them:
#   git add skills && git commit -m "fix: narrow skill descriptions to remove trigger overlap"
git tag -a zeroclaw-v0.8.3 -m "Verified against ZeroClaw v0.8.3"
git log --oneline
```

- [ ] **Step 8: Remove the verification worktree**

```bash
git -C ~/prj/zeroclaw worktree remove \
  /tmp/claude-1000/-home-jfd-prj-zeroclaw/eda80a89-61cb-4e86-9608-c8fa6d4e200b/scratchpad/zc-v083
git -C ~/prj/zeroclaw worktree list
```

Expected: the `zc-v083` worktree no longer appears; `~/prj/zeroclaw` on
`master` is untouched.
