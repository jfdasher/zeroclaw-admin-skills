---
name: zeroclaw-introspect
description: Interrogates a running ZeroClaw instance for runtime state and its own configuration - status, component health, effective security posture, config values, cost, sessions, and logs. Use when asked what an agent is doing, whether the daemon is healthy, what a config value is set to, why a channel is failing, or to troubleshoot a ZeroClaw instance. Read-only; use zeroclaw-agents or zeroclaw-mcp to change anything.
---

# Interrogating a ZeroClaw instance

Verified against **ZeroClaw v0.8.3**.

This skill is **read-only**. It never mutates config. For concepts, see the
`zeroclaw-orientation` skill.

**Where you are running matters.** The CLI commands here need a shell on the
daemon's host — directly or over SSH. The `curl` examples need only network reach
to the gateway. Both are first-class: many instances keep the gateway bound to
`127.0.0.1` and publish it, along with the browser admin plane at `/`, through a
same-host reverse proxy such as `tailscale serve`.

Two consequences if you are working through such a proxy:

- The gateway sees the proxy's loopback address, not yours, so `/admin/*`
  answers **without a token** — including `/admin/reload`, regardless of
  `allow_remote_admin`. Useful, and important to understand before auditing a
  deployment. See `references/gateway-endpoints.md`.
- Over SSH, the binary may not be on a non-interactive `PATH`. Use
  `$HOME/.cargo/bin/zeroclaw` if a bare `zeroclaw` returns `command not found`.

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

**5. Get a bearer token if you need any `/api/*` endpoint.**

Only `/health` and `/metrics` are public. **Every `/api/*` route returns `401`
without a bearer token**, even from loopback, whenever `gateway.require_pairing`
is true — which is the default. The error body is explicit:

```json
{"error":"Unauthorized — pair first via POST /pair, then send Authorization: Bearer <token>"}
```

Pair from the ZeroClaw host (the pairing-code endpoint is localhost-only):

```sh
CODE=$(curl -s -X POST http://localhost:42617/admin/paircode/new | jq -r .pairing_code)
export ZC_TOKEN=$(curl -s -X POST http://localhost:42617/pair \
  -H "X-Pairing-Code: $CODE" | jq -r .token)
echo "${ZC_TOKEN:0:8}…"   # tokens look like zc_<64 hex chars>
```

Two traps worth knowing:

- The pairing route is **`/pair`**, not `/api/pair`. `/api/pair` exists but
  requires `Content-Type: application/json` and rejects the header-only form
  with `415 Unsupported Media Type`.
- `GET /admin/paircode` returns `"pairing_code": null` once the instance is
  already paired. Use `POST /admin/paircode/new` to mint a fresh one.

Every `/api/*` example below assumes `$ZC_TOKEN` is set. If you only need
liveness and component health, skip this — `/health` needs no token.

> **Pairing is close to one-way. Do not mint tokens casually.** Each successful
> pair appends to `gateway.paired_tokens`, and there is no supported way to
> remove one entry: `config patch` rejects positional array removal
> (`property path not found in schema: gateway.paired_tokens.2`), and there is no
> unpair command — `zeroclaw gateway` offers only `start`, `restart`, and
> `get-paircode`. The only route back is rewriting the whole list with
> `config set gateway.paired_tokens '[...]'`, which requires every value you
> intend to keep, and reads never return secret values. Check for an existing
> token before pairing, and prefer the CLI when it can answer the question.

Admin routes are the exception in the other direction: `POST /admin/reload`
succeeds from loopback with **no** token at all.

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

**Cost and token spend** (broken down by agent under `.cost.by_agent`):

```sh
curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/cost | jq
```

**Tools currently registered**, with descriptions and parameter schemas:

```sh
curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/tools | jq
```

**Sessions:**

```sh
curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/sessions | jq
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

**Discover paths and types without guessing.** `config list --filter` is the
tool for this — it prints every reachable path under a prefix with its current
value and Rust type:

```sh
zeroclaw config list --filter agents.example_agent
```

```text
  agents.example_agent.enabled         = true         (bool)
  agents.example_agent.channels        = ["cli"]      (Vec<crate::providers::ChannelRef>)
  agents.example_agent.model_provider  = <alias>      (crate::providers::ModelProviderRef)
  agents.example_agent.risk_profile    = <alias>      (crate::providers::RiskProfileRef)
```

Over the gateway, `GET /api/config/list?prefix=<dotted>` returns the same thing
as JSON with `kind`, `type_hint`, `populated`, and `is_secret` per entry.

> **Do not use `zeroclaw config schema --path <dotted>` for this.** At v0.8.3 the
> `--path` argument is **silently ignored**: every invocation dumps the entire
> ~1.28 MB whole-config schema, and a nonexistent path still exits 0 rather than
> erroring. Verified on a live v0.8.3 daemon — `--path agents`,
> `--path mcp.servers`, and `--path totally.bogus.path` all returned the same
> full document. `OPTIONS /api/config/prop?path=…` has the same defect (~1 MB).
> Reach for `config list --filter` instead; it actually scopes.

**Check whether one secret is populated.** Prefer the gateway — it never
decrypts anything and answers exactly the question:

```sh
curl -s -H "Authorization: Bearer $ZC_TOKEN" \
  "http://localhost:42617/api/config/prop?path=channels.telegram.default.bot_token"
# {"path":"channels.telegram.default.bot_token","populated":true}
```

**To inventory every secret field at once**, the CLI is the only option:

```sh
zeroclaw config list --secrets
```

> **This command is not uniformly masked.** Scalar secrets (`Option<String>`,
> `String`) render as `****`, but on a live v0.8.3 instance
> `gateway.paired_tokens` — a `Vec<String>` secret — **prints every token in
> full**. Assume list-valued secrets leak their contents here. Treat the output
> as sensitive: do not paste it into files, tickets, or transcripts, and expect
> policy-restricted environments to refuse the command outright. When you need a
> population check rather than a full inventory, use the endpoint above.

> **The API surface genuinely never returns secret values.**
> `GET /api/config/prop` reports `{path, populated}` — no value, no length, no
> mask, no hash — and `GET /api/config` masks them. If asked to show an API key,
> explain that no supported path returns one and report population instead.

## Logs

```sh
# Linux, user service
journalctl --user -u zeroclaw -f
journalctl --user -u zeroclaw --since "1 hour ago"

# macOS and Windows write files instead
tail -f ~/.zeroclaw/logs/daemon.stderr.log
```

Over the gateway: `curl -s -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/logs | jq`

## Live event stream

```sh
curl -N -H "Authorization: Bearer $ZC_TOKEN" http://localhost:42617/api/events
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
| `401` from any `/api/*` route | Expected without a token, even on loopback. Pair and set `$ZC_TOKEN` (Discovery step 5) |
| `403` from `/admin/*` | Non-loopback caller. Needs `allow_remote_admin = true` **and** pairing enabled |
| `415` from `POST /api/pair` | Wrong route for the header form — use `POST /pair` instead |
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
