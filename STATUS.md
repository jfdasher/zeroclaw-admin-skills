# STATUS

**Target:** ZeroClaw v0.8.3
**State:** all five skills complete, source-verified and live-verified
**Last verification:** 2026-07-25

## Where things stand

| Skill | Source-verified | Live-verified | Notes |
|---|:--:|:--:|---|
| `zeroclaw-orientation` | yes | yes | Alias grammar confirmed against all five rejection cases |
| `zeroclaw-introspect` | yes | yes | Corrected after live testing — see defect 1 and 2 below |
| `zeroclaw-agents` | yes | yes | Full CRUD cycle exercised, including `--dry-run` non-destructiveness |
| `zeroclaw-mcp` | yes | yes | Corrected after live testing — see defect 3 below |
| `zeroclaw-skills-tools` | yes | yes | Bundle → install → `list --agent` workflow exercised end to end |

`validate.sh` passes. 43 of 48 claims passed on the first live run; all five
failures were real defects in the skills, now fixed and covered by regression
guards.

## What live testing changed

Source reading caught the drift between ZeroClaw's docs and its code. It did
**not** catch these three — only running the commands did. This is the main
lesson of the project so far.

**1. `/api/*` authentication.** Every `/api/*` route requires a bearer token,
even from loopback, under the default `require_pairing = true`. The skills
originally showed bare `curl`, which returns `401` on any default install. The
pairing procedure (`POST /admin/paircode/new` → `POST /pair`) is now documented,
along with two traps: it is `/pair` and not `/api/pair` (which wants a JSON
content-type and answers the header form with `415`), and `GET /admin/paircode`
returns null once already paired.

**2. `config schema --path` is a no-op.** The `--path` argument is silently
ignored; every invocation returns the whole ~1.28 MB config schema, and a bogus
path exits 0 rather than erroring. `OPTIONS /api/config/prop?path=…` has the same
defect. Three skills recommended this as the "don't guess field names" tool —
advice that would flood a context window and silently succeed on a typo.
Replaced with `config list --filter`, which genuinely scopes.

**3. MCP server creation.** `mcp.servers` is a `Vec<McpServerConfig>`, not a map,
so `config set mcp.servers.<new>.<field>` fails with `Unknown property` and a
`config patch` `add` to `/mcp/servers/-` fails too. Creation requires
`POST /api/config/map-key?path=mcp.servers&key=<name>` or an `[[mcp.servers]]`
TOML append; `config set` works only *after* the entry exists. `mcp_bundles`
*is* a real map and accepts `config set` directly. That asymmetry is the single
most confusing thing about configuring MCP, and it is now called out explicitly.

## Second live round — 2026-07-25

Found while doing real administration work on a v0.8.3 instance, not while
testing the skills. Both were gaps rather than errors: the skills were silent
where they should have spoken.

**4. Structural config change was undocumented.** Removing a whole alias entry
is impossible through `config set` *or* `config patch` — `remove` on
`/mcp_bundles/mail` fails with `property path not found in schema`, exactly like
the creation case in defect 3. The full map-key family
(`GET /api/config/map-keys`, `POST`/`DELETE /api/config/map-key`,
`POST /api/config/rename-map-key`) was verified in the router at v0.8.3 and
exercised live; `DELETE` and rename reach the same cascade engine as the CLI's
`delete`/`rename` for aliased sections. `DELETE` returns `{"created": false}` on
success — a shared response literal, not a failure. The three-tier model
(field / structure / list) now lives in `zeroclaw-orientation`, with mechanics in
`references/config-model.md` and routes in `zeroclaw-introspect`'s
`references/gateway-endpoints.md`.

**5. `config list --secrets` is not uniformly masked.** Scalar secrets render as
`****`, but `gateway.paired_tokens` — a `Vec<String>` secret — prints every token
in full on a live instance. Skills recommended the command as a safe population
check; `zeroclaw-introspect` and `zeroclaw-mcp` now point at
`GET /api/config/prop` instead, which returns `{path, populated}` without
decrypting, and the `--secrets` output carries a handling warning. The claim that
reads report "no value, no length, no mask, no hash" remains true of the **API**;
it was never true of that CLI command.

Also documented, both verified live: **pairing is close to one-way** — each pair
appends to `gateway.paired_tokens`, positional array removal is rejected, and
`zeroclaw gateway` has no unpair subcommand — and **"loopback" means the socket's
peer address**, so a same-host reverse proxy makes the unauthenticated `/admin/*`
tier reachable by anyone who can reach the proxy, regardless of
`allow_remote_admin`.

## Confirmed correct

Verified against a live daemon and behaving as documented: the alias grammar
(hyphen, uppercase, `__`, leading underscore, and >63 characters all rejected);
`agents create/rename/delete` including `--dry-run` genuinely not deleting;
`read_only` rejected as an autonomy level; the **API** returning `populated` with
no value, length, mask, or hash (but see defect 5 for the CLI); the absence of a
`zeroclaw mcp` subcommand; the
absence of a `--skill` flag on `skills install`; hyphen rejection on bundle
aliases alongside hyphen *requirement* on skill directory names; MCP default-deny
for an agent with no bundles; `/admin/reload` succeeding from loopback without a
token; and the full skill-bundle workflow through `skills list --agent`.

## Known gaps

**Not covered by any skill.** Deliberately out of scope for the initial set, and
candidates for later work: channels beyond what agent wiring requires (`channels`
CRUD is covered, but not per-platform setup), cron and scheduling, SOPs, memory
management, hardware and peripherals, delegation and peer groups, and the
`zerocode` terminal UI.

**Not verified.** A few things are documented from source but never exercised
live: the `estop` family (disruptive to test on a working instance), OTP gating,
and sandbox backend selection. They are described conservatively; treat them as
source-verified only.

**Remote operation.** *(Addressed 2026-07-25.)* The skills no longer assume a
local vantage point. Each opening line now separates CLI commands (need a shell
on the host, directly or over SSH) from `curl` examples (need only gateway
reach), and `zeroclaw-introspect` documents the reverse-proxy deployment where
the gateway stays bound to `127.0.0.1` and is published — along with the browser
admin plane at `/` — through `tailscale serve` or similar. The
`allow_remote_admin` semantics under a proxy are covered in
`references/gateway-endpoints.md`.

**Eval coverage is nominal.** Each skill ships `evals/evals.json` with trigger and
non-trigger cases, but there is no harness that runs them. They document intent
and would need a runner to catch regressions automatically.

## Maintenance triggers

Re-verify when any of these happen:

- **ZeroClaw is upgraded.** Follow the re-verification recipe in
  `COMPATIBILITY.md`, then update the pin in `validate.sh`, `COMPATIBILITY.md`,
  and every `SKILL.md` opening line.
- **A skill fires on the wrong prompt.** Descriptions are the whole triggering
  mechanism; narrow the weaker of the two and re-check the set for disjointness.
- **Any of the three defects above is fixed upstream.** The corrected guidance
  will then be describing a bug that no longer exists.

## Non-goals

Mirroring ZeroClaw's manual. These skills exist to encode what is *true* about a
specific version and what is *operationally load-bearing* — the traps, the
orderings, the fail-closed defaults. Where the upstream docs are correct and
complete, link to them rather than copying.
