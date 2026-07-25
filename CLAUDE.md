# CLAUDE.md — zeroclaw-admin-skills

Guidance for Claude Code when working **in this repository**.

This repo contains Claude Code skills that administer a [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw)
instance. It is a documentation repository: the "source" is Markdown, and the
"build" is a set of symlinks into `~/.claude/skills/`.

## The one rule that matters

**Every command, flag, config path, and endpoint written into a skill must be
verified against the pinned ZeroClaw version before it is committed.**

Not against ZeroClaw's documentation — against its source, and ideally against a
running daemon. This is not pedantry. The current pin is v0.8.3, and verification
has already caught:

- Commands the mdbook documents that do not exist in the binary
- Help text that contradicts the validator it describes
- A CLI flag that is silently ignored
- A config section whose documented write path does not work

If you cannot verify a claim, **omit it**. A skill that is silent on a topic is
strictly better than one that is confidently wrong, because the reader cannot
tell the difference until it fails.

## Verification workflow

Source of truth is a worktree at the pinned tag:

```sh
git -C /path/to/zeroclaw worktree add --detach /tmp/zc-verify v0.8.3
```

| Claim about | Check in |
|---|---|
| CLI commands and flags | `src/main.rs` (`enum Commands`, `enum ConfigCommands`), `src/lib.rs` (`enum AgentsCommands`, `enum SkillCommands`, `enum SkillBundleCommands`) |
| Config paths, types, secret markers | `crates/zeroclaw-config/src/schema.rs` |
| Alias naming rules | `crates/zeroclaw-config/src/helpers.rs` (`validate_alias_key`) |
| Gateway routes | `crates/zeroclaw-gateway/src/lib.rs` |

Source reading is necessary but **not sufficient**. Three of the defects found so
far survived a careful source read and were only caught by running the commands
against a live daemon. If a change touches runtime behavior, run it. See
`tests/README.md`.

## Repository layout

```
skills/<name>/SKILL.md          the skill itself
skills/<name>/references/*.md   loaded on demand, not up front
skills/<name>/evals/evals.json  trigger cases
tests/                          live-instance claim tests
validate.sh                     structural checks — the test suite
install.sh                      symlinks skills/* into ~/.claude/skills/
COMPATIBILITY.md                the version pin and what verification found
STATUS.md                       current state and known gaps
```

## Conventions

**Frontmatter is the product.** A skill only helps if it fires. `name` must match
the directory. `description` must state what the skill does *and* when to use it,
and must be disjoint from its siblings — say explicitly what a skill is *not*
for when a neighbor is the better fit.

**`zeroclaw-orientation` owns shared concepts.** The alias grammar, the
agent-as-a-join model, and the install layout are defined there once. Other
skills link to it rather than restating. Do not duplicate those definitions.

**Progressive disclosure.** `SKILL.md` holds the workflow. Field tables, endpoint
inventories, and format references go in `references/` so they load only when
needed.

**Mutation posture.** Skills execute reads, creates, and grants directly. They
stop and require explicit confirmation before `agents delete`, `providers
delete`, `channels delete`, `skills bundle remove`, `estop`, and `memory clear`.
Confirmation is written into the skill, not left to model judgment.

**The four-beat loop.** Every mutating workflow ends the same way: read effective
state → dry-run where supported → apply → **reload and verify**. Beat four is not
optional; `config set` writes the file but daemon-owned subsystems do not adopt
it until a reload.

**Every SKILL.md states its version pin in the opening line.** `validate.sh`
enforces this.

## Before committing

```sh
./validate.sh          # must exit 0
```

The validator checks frontmatter, name/directory agreement, the version pin, eval
JSON validity, and greps for known-nonexistent flags. When live testing disproves
a claim, add a guard so the mistake cannot silently return.

## Publishing hygiene

This repository is public. It must never contain:

- Hostnames, agent aliases, provider aliases, or profile names from a real deployment
- Bearer tokens, pairing codes, API keys, or encrypted config values
- IP addresses — use `localhost` in examples
- Absolute paths containing a real username
- Verbatim excerpts of anyone's `config.toml`

Examples use obvious placeholders: `example_agent`, `<alias>`, `$ZC_TOKEN`.
Audit **git history**, not just the working tree — a scrubbed file with a leaky
parent commit is still a leak.

## Working with a live instance

If asked to test against a real deployment: back it up first, verify the backup
restores, and prefer a scratch host. Note that pairing persists a bearer token
into config on **every** call — repeated test runs accumulate live credentials,
and revoking them means restoring the prior `paired_tokens` list, because new
tokens are not appended predictably.

Never commit anything observed on a live instance without scrubbing it first.
