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

## Mutating config structure

Config mutation has **three tiers**, and they are not interchangeable. Reaching
for the wrong one is the most common way to waste a session, because the failure
is a schema error that reads like the path is wrong when the *mechanism* is
wrong.

| Tier | What it changes | How |
|---|---|---|
| Field | A value inside an entry that already exists | `zeroclaw config set <dotted> <value>`, or `PATCH /api/config` |
| Structure | A whole alias entry — creating or removing one | The map-key endpoints only |
| Array elements | Adding or removing list items positionally | **Not supported** |

**Fields.** `config set` and JSON Patch operate on paths the schema can resolve.
They edit what is there; they cannot bring an entry into being or take one away.

**Structure.** Adding or removing an alias — an agent, a channel, a provider, a
bundle, a peer group — goes through the map-key family:

```sh
# create
curl -s -X POST -H "Authorization: Bearer $ZC_TOKEN" \
  "http://localhost:42617/api/config/map-key?path=mcp_bundles&key=research"

# remove
curl -s -X DELETE -H "Authorization: Bearer $ZC_TOKEN" \
  "http://localhost:42617/api/config/map-key?path=mcp_bundles&key=research"

# enumerate, to confirm
curl -s -H "Authorization: Bearer $ZC_TOKEN" \
  "http://localhost:42617/api/config/map-keys?path=mcp_bundles"
```

**`DELETE` returns `{"created": false}` on success** — a shared response struct,
not a failure signal. Verify with `map-keys`, not the response body.

Where a CLI equivalent exists, prefer it: `zeroclaw agents delete`,
`channels delete`, and `providers delete` reach the *same* cascade engine as the
endpoint and add `--dry-run`, which the HTTP route has no equivalent for. The
map-key endpoints are the right tool for sections the CLI does not cover —
`mcp_bundles`, `skill_bundles`, `peer_groups`.

**Arrays.** There is no positional insert or remove. Both of these fail:

```text
config patch  remove /mcp_bundles/mail          → property path not found in schema: mcp_bundles.mail
config patch  remove /gateway/paired_tokens/2   → property path not found in schema: gateway.paired_tokens.2
```

The first is a *structure* change wearing an array-ish path — use map-key. The
second is genuinely unsupported: to change a list you rewrite the whole list with
`config set <path> '["a","b"]'`. For a list of secrets, such as
`gateway.paired_tokens`, that means having every value you intend to keep in hand
first, since reads never return them. **Pairing is therefore effectively
one-way** — see `zeroclaw-introspect`.

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
