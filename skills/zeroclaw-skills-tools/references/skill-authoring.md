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
