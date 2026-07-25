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

> `skills install` at v0.8.3 accepts only `--agent`, `--bundle`, and
> `--no-tier-banner`. Some documentation shows a `--skill <name>` option for
> installing one skill from a catalog repository; that flag does not exist in
> this version.

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
curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/tools | jq '.[].name'
zeroclaw security status --agent <alias>
```

`/api/tools` requires a bearer token (`401` without one, even on loopback); see
`zeroclaw-introspect` Discovery step 5. `zeroclaw security status` is CLI-only
and needs no token.

A tool can be present but unusable: the risk profile's `excluded_tools`, or a
channel's `excluded_tools`, hides it. A tool excluded at the channel level is
never advertised to the model on that channel. For MCP specifically, see the
`zeroclaw-mcp` skill.

For frontmatter fields, `SKILL.toml` structure, and slash-command options, read
`references/skill-authoring.md`.
