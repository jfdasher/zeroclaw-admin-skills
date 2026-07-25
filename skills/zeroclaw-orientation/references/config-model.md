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
