# Gateway endpoints (v0.8.3)

Default bind: `localhost:42617`. Routes verified against
`crates/zeroclaw-gateway/src/lib.rs` at tag v0.8.3, and confirmed against a live
v0.8.3 daemon.

## Authentication, first

Three tiers, and confusing them is the most common cause of a wasted debugging
session:

| Tier | Routes | Requirement |
|---|---|---|
| Public | `/health`, `/metrics` | Nothing |
| Bearer | **every** `/api/*` route | `Authorization: Bearer <token>` — required even on loopback whenever `gateway.require_pairing` is true (the default) |
| Loopback-admin | `/admin/reload`, `/admin/paircode*` | Loopback needs no token. Remote needs `allow_remote_admin = true` **and** pairing |

Obtaining a token, from the ZeroClaw host:

```sh
CODE=$(curl -s -X POST http://localhost:42617/admin/paircode/new | jq -r .pairing_code)
export ZC_TOKEN=$(curl -s -X POST http://localhost:42617/pair \
  -H "X-Pairing-Code: $CODE" | jq -r .token)
```

Tokens are `zc_` followed by 64 hex characters. Two observed gotchas:

- Pair against **`/pair`**. `/api/pair` requires `Content-Type: application/json`
  and answers the header-only form with `415 Unsupported Media Type`.
- `GET /admin/paircode` yields `"pairing_code": null` on an already-paired
  instance. `POST /admin/paircode/new` mints a fresh code.

## Read-only

`Auth` column: **—** public, **B** bearer required.

| Endpoint | Auth | Returns |
|---|:--:|---|
| `GET /health` | — | Status, pairing state, runtime component map |
| `GET /metrics` | — | Prometheus text exposition; needs `[observability] backend = "prometheus"` |
| `GET /api/health` | B | Authenticated health equivalent |
| `GET /api/status` | B | Same information as `zeroclaw status`, as JSON |
| `GET /api/cost` | B | Cost and token counts; `.cost.by_agent` breaks down per agent |
| `GET /api/tools` | B | Registered tools with descriptions and parameter schemas |
| `GET /api/sessions` | B | Active sessions; `/api/sessions/running` for running only |
| `GET /api/logs` | B | Recent log lines |
| `GET /api/channels` | B | Configured channels |
| `GET /api/events` | B | SSE stream; `/api/events/history` replays the buffer |
| `GET /api/memory` | B | Memory entries; `?query=` and `?category=` filter |
| `GET /api/cron` | B | Scheduled jobs |
| `GET /api/skills/bundles` | B | Configured skill bundles |
| `GET /api/docs` | — | Scalar API explorer; `/api/openapi.json` for the raw spec |

## Config

All of these are `/api/*` and therefore bearer-authenticated.

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
