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
| `GET /api/devices` | B | Paired devices: `id`, `name`, `device_type`, `ip_address`, `paired_at`, `last_seen` |
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
| `GET /api/config/map-keys?path=<section>` | List the aliases in a map-keyed section |
| `POST /api/config/map-key?path=<section>&key=<alias>` | **Create** a map key |
| `DELETE /api/config/map-key?path=<section>&key=<alias>` | **Remove** a map key |
| `POST /api/config/rename-map-key` | Rename a map key. JSON body `{path, from, to}` |

### The map-key family

These four are the **only** way to add or remove *structure* — a whole alias
entry — from config. `config set` and `PATCH` edit fields inside structure that
already exists; neither can create or delete an alias. See "Mutating config
structure" in `zeroclaw-orientation`'s `config-model.md` for the full model.

`path` and `key` are both required on create and delete; omitting either yields
`Failed to deserialize query string`.

Two response traps:

- **`DELETE` returns `{"created": false}` on success.** The handler shares one
  response struct with `POST` and hardcodes `created: false`. It is not an error
  and not a "nothing happened" signal. Confirm removal with
  `GET /api/config/map-keys`, not by reading the response.
- **A `warnings` array may appear on agent deletion**, and is omitted when empty.
  Non-empty means the *config* delete succeeded but one or more owned-state side
  effects did not — workspace archive, memory/cron/acp purge, session
  attribution. Inspect the archive directory before reusing the alias. Never
  treat a 200 carrying warnings as a clean delete.

For aliased sections (`agents`, `channels.*`, `providers.*`, `risk_profiles`, …)
`DELETE` and rename route through the **same cascade engine** as the CLI's
`delete` and `rename`, scrubbing inbound references identically. Agent deletion
additionally refuses on hard references — an enabled `heartbeat.agent` or a live
ACP session — and **fails closed** if the session store cannot be read.
Non-aliased sections (`mcp_bundles`, `skill_bundles`, `peer_groups`) get a plain
key removal with no cascade.

`OPTIONS` returns capabilities; `GET` returns current values. The `Allow` header
on `OPTIONS /api/config` still advertises legacy `PUT`, which the router does not
register — ignore it.

## Devices — the only supported unpair

| Endpoint | Purpose |
|---|---|
| `GET /api/devices` | Inventory of paired devices |
| `DELETE /api/devices/{id}` | Revoke a device; drops its token hash from `gateway.paired_tokens` |
| `POST /api/devices/{id}/token/rotate` | Rotate one device's token, leaving others untouched |
| `GET`/`POST /api/devices/me/capabilities` | Capabilities of the calling device |

`gateway.paired_tokens` stores `PairingGuard::token_hash(&token)` — hashes, not
bearer tokens. It is subsystem-owned: entries arrive by pairing and leave by
revoking, never by editing the list.

Revoke the device you are authenticating with **last**; it ends your own session.
The two stores can diverge — a live instance showed 14 device records against 3
token hashes, because ad-hoc pairings accumulate device rows. `GET /api/devices`
is the honest inventory.

## Admin

| Endpoint | Access |
|---|---|
| `POST /admin/reload` | Loopback always allowed, no token. Remote requires `gateway.allow_remote_admin = true` **and** pairing enabled |
| `POST /admin/shutdown` | Localhost only, regardless of `allow_remote_admin` |
| `GET /admin/paircode` | Localhost only |

`allow_remote_admin` has no effect unless `require_pairing` is also on: with
pairing disabled a remote caller cannot be authenticated, so the request is
rejected rather than allowed anonymously.

### "Loopback" means the socket's peer address

A reverse proxy on the same host — `tailscale serve`, nginx, Caddy — connects to
the gateway *from* loopback. The gateway sees the proxy, not the original
client, so **every proxied request is treated as a loopback caller** and the
unauthenticated `/admin/*` tier applies to anyone who can reach the proxy.

This is the normal way ZeroClaw's browser admin plane is published: the gateway
stays bound to `127.0.0.1`, `gateway.web_dist_dir` serves the UI at `/`, and the
proxy fronts it. Verified against a live v0.8.3 instance behind
`tailscale serve`: `POST /admin/reload` and `GET /admin/paircode` both answer
`200` unauthenticated from a different host on the tailnet, while `/api/*`
still answers `401`. `allow_remote_admin = false` does not change this — it
gates on peer address, and the peer address is loopback.

Consequences worth stating plainly when auditing a deployment:

- The proxy's own access control **is** the admin perimeter. For `tailscale
  serve` that is the tailnet plus its ACLs and any node sharing.
- `POST /admin/paircode/new` is reachable the same way, so anyone who can reach
  the proxy can mint a pairing code, exchange it at `/pair`, and obtain a full
  bearer token. The `401`s on `/api/*` are not a second line of defence.
- `gateway.trust_forwarded_headers` exists for exactly this shape. If a
  deployment needs `/admin/*` restricted to the real host, that is the knob to
  investigate — but verify the resulting behavior rather than assuming it.

None of this is a defect. It is the intended deployment model, and it is why
this skill family does **not** assume administration happens over SSH.

## The route inventory caveat

The OpenAPI document at `/api/openapi.json` is assembled separately from the
router and does not cover every registered route. The router in
`crates/zeroclaw-gateway/src/lib.rs` is the authority for what actually exists.
