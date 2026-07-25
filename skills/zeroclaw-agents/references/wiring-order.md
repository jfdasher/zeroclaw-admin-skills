# Reference wiring order and CRUD surfaces

Verified against ZeroClaw v0.8.3.

## Safe creation order

Build from the leaves inward. Each step's targets must exist before the next
step points at them.

1. **Model provider** — `zeroclaw providers create models <family> <alias>`,
   then set `api_key` and `model`.
2. **Risk profile** — `[risk_profiles.<alias>]`. Created via `zeroclaw config set
   risk_profiles.<alias>.level supervised` (writing a field instantiates the
   section) or `zeroclaw config init risk_profiles`.
3. **Runtime profile** — `[runtime_profiles.<alias>]`, same pattern.
4. **Channels** — `zeroclaw channels create <type> <alias>`, then set the
   channel's credentials.
5. **Agent** — `zeroclaw agents create <alias>`.
6. **Wire the agent** — set `model_provider`, `risk_profile`, `runtime_profile`,
   and channel bindings.
7. **Reload** — `curl -X POST http://localhost:42617/admin/reload`.
8. **Verify** — `zeroclaw security status --agent <alias>` and a live
   `zeroclaw agent -a <alias> -m "hello"`.

Deleting runs in reverse: delete the agent first (its cascade scrubs its own
references), then the targets it pointed at.

## CRUD surfaces

All three share the same shape. Verified against `enum AgentsCommands`,
`enum ProvidersCommands`, and `enum ChannelsCommands` in `src/lib.rs`.

| Command | Signature |
|---|---|
| `zeroclaw agents list` | — |
| `zeroclaw agents create` | `<alias>` |
| `zeroclaw agents rename` | `<from> <to>` |
| `zeroclaw agents delete` | `<alias> [--dry-run] [--yes]` |
| `zeroclaw providers list` | `[--category <models\|tts\|transcription>]` |
| `zeroclaw providers create` | `<category> <family> <alias>` |
| `zeroclaw providers rename` | `<category> <family> <from> <to>` |
| `zeroclaw providers delete` | `<category> <family> <alias> [--dry-run] [--yes]` |
| `zeroclaw channels list` | `[--channel-type <type>]` |
| `zeroclaw channels create` | `<channel_type> <alias>` |
| `zeroclaw channels rename` | `<channel_type> <from> <to>` |
| `zeroclaw channels delete` | `<channel_type> <alias> [--dry-run] [--yes]` |

## Discovering fields instead of guessing

Use `zeroclaw config list --filter <prefix>`. It prints every reachable path
under the prefix with its current value and Rust type:

```sh
zeroclaw config list --filter agents
zeroclaw config list --filter risk_profiles
zeroclaw config list --filter runtime_profiles
```

**Not `config schema --path`.** At v0.8.3 that argument is silently ignored —
every invocation returns the entire ~1.28 MB whole-config schema, and a bogus
path exits 0. Verified against a live v0.8.3 daemon.

## Batch changes

For several related edits that must land together, use a JSON Patch document.
It applies atomically: every operation runs against an in-memory copy, the whole
config is validated once, and nothing is persisted if any operation or the final
validation fails.

```sh
cat <<'EOF' | zeroclaw config patch -
[
  {"op": "replace", "path": "/agents/example_agent/model_provider", "value": "anthropic.prod"},
  {"op": "replace", "path": "/agents/example_agent/risk_profile", "value": "hardened"}
]
EOF
```

Both JSON Pointer (`/agents/example_agent/...`) and dotted
(`agents.example_agent....`) path forms are accepted. Supported operations are
`add`, `replace`, `remove`, and `test`. `move` and `copy` are rejected with
`op_not_supported`. A `test` against a secret path is rejected with
`secret_test_forbidden`, because a differential outcome would leak the value.
