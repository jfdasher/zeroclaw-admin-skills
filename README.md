# zeroclaw-admin-skills

Claude Code skills for administering a [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw)
instance — understanding it, interrogating it, managing agents, and provisioning
MCP servers and tooling.

Every command in these skills is verified against the ZeroClaw **source** at a
pinned version, and then against a **running daemon**. Where ZeroClaw's own
documentation and its code disagree, the code wins. See
[COMPATIBILITY.md](./COMPATIBILITY.md) for what that turned up.

> **Two different things are called "skills."** These are *Claude Code* skills,
> invoked via the `Skill` tool. ZeroClaw has a separate feature also called
> skills (`SKILL.md`/`SKILL.toml` installed into an agent's bundle).
> `zeroclaw-skills-tools` is a Claude Code skill *about* that ZeroClaw feature.

## The skills

| Skill | Use it for |
|---|---|
| **`zeroclaw-orientation`** | What ZeroClaw is and how its config model works: the agent-as-a-join model, the alias reference graph, naming rules, install layout. No running instance needed. Start here. |
| **`zeroclaw-introspect`** | Interrogating a live instance: status, component health, effective security posture, config values, cost, sessions, logs. Read-only. |
| **`zeroclaw-agents`** | Agent lifecycle: creating, wiring, renaming, deleting agents and the provider/channel/profile aliases they reference. |
| **`zeroclaw-mcp`** | Granting MCP servers to agents through config bundles, and diagnosing why an agent cannot see MCP tools. |
| **`zeroclaw-skills-tools`** | Installing and auditing ZeroClaw's own skills and bundles; working out which tools an agent actually loads. |

They are meant to be invoked individually — the descriptions are written to be
mutually disjoint so the right one fires — but `zeroclaw-orientation` is the hub
the others link to for shared concepts.

## Install

```sh
git clone https://github.com/<you>/zeroclaw-admin-skills.git
cd zeroclaw-admin-skills
./install.sh
```

`install.sh` symlinks each `skills/<name>` into `~/.claude/skills/<name>`, so a
later `git pull` updates your installed skills with no reinstall step.

```sh
./install.sh --dry-run   # show what would happen
./install.sh --force     # replace stale symlinks
```

It is idempotent and refuses to overwrite anything that is not a symlink it owns.
Set `CLAUDE_SKILLS_DIR` to install somewhere other than `~/.claude/skills`.

## Assumptions

- **ZeroClaw v0.8.3.** Other versions may differ; ZeroClaw moves quickly. See
  [COMPATIBILITY.md](./COMPATIBILITY.md) for how to re-verify after an upgrade.
- **Local vantage point.** The skills assume your Claude Code session runs on the
  same host as the daemon, so they lead with the `zeroclaw` CLI and use the HTTP
  gateway only where the CLI has no equivalent.
- **`jq`** for the gateway examples.

## A taste of what verification caught

These are documented behaviors that turn out not to hold at v0.8.3 — the reason
this repo exists rather than pointing you at the manual:

- `zeroclaw config schema --path <dotted>` **silently ignores `--path`**, dumping
  the entire ~1.28 MB whole-config schema. A nonexistent path exits 0.
- **Every `/api/*` route requires a bearer token**, including from loopback.
  Only `/health` and `/metrics` are public — while `/admin/reload` needs no token
  from loopback at all.
- `mcp.servers` is a `Vec`, not a map, so a new MCP server **cannot** be created
  with `config set` or `config patch`. Meanwhile `mcp_bundles` *is* a map and can.
- Config aliases reject hyphens; ZeroClaw skill directory names require them.
  Two namespaces, opposite rules — and one `--help` string gets it backwards.

## Development

```sh
./validate.sh   # structural checks: frontmatter, version pins, eval JSON
```

`tests/` holds scripts that assert the skills' claims against a live daemon. They
mutate config and clean up after themselves; read [tests/README.md](./tests/README.md)
before running one, and back up your instance first.

Contributions should follow [CLAUDE.md](./CLAUDE.md) — in particular, verify
before you write, and omit what you cannot verify.

Current state and known gaps: [STATUS.md](./STATUS.md).

## License

MIT. See [LICENSE](./LICENSE).
