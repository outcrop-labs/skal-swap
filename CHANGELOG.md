# Changelog

## 1.3.0

### Per-profile output length, so long answers stop getting truncated

Claude Code caps a single response at 32000 tokens and then fails it outright
with `API Error: Claude's response exceeded the 32000 output token maximum`,
which is a rotten way to find out halfway through a long file.

The real ceiling now gets declared as `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, read
off the endpoint rather than typed in:

- The model catalogue already behind the picker often reports the cap
  (`max_tokens` on Anthropic, `top_provider.max_completion_tokens` on
  OpenRouter, `max_output_tokens` elsewhere), and whichever model the profile
  is pinned to decides the number.
- Covers the OAuth profile too: its catalogue is Anthropic's, read with the
  live login, and an alias pin like `opus` resolves to the newest Opus listed.
- A bare `max_tokens` counts only alongside a separate input/context field,
  and is dropped when it equals that window, because plenty of OpenAI-shaped
  listings reuse the name for the context length.
- New optional `max_output` key in `profiles.conf` overrides all of it, and is
  the only way to raise the cap on the many endpoints (Z.ai and Alibaba's
  token-plan gateway included) that report no limits at all.
- Managed like the rest of the env: switching to a profile with no cap to
  declare removes the key and restores Claude Code's default.
- The model cache gained a column, so it is versioned `v3` and refetches
  once.

### Catalogue fetches are size-capped

Model-catalogue responses had a 10 second timeout but no size limit, and the
whole body was held in memory on its way to `jq`, so a provider that
misbehaved or was compromised could stream until something gave. They now
carry a hard 4 MiB ceiling (`curl --max-filesize`, re-checked against the
received byte count for the curl builds that treat the flag as advisory on a
chunked response). Over the ceiling the transfer is aborted and the endpoint
is skipped, which is the same path as any other failed probe: the profile
still switches, on its configured model. The largest real catalogue going is
OpenRouter's at roughly 730 KB. Reported by @HANCORE-linux, with thanks.

## 1.2.0

### Per-profile context length, so auto-compact works

Claude Code never auto-compacted on provider profiles: hand it a model id it
doesn't know and it assumes a 200k window, then only warns about that number
instead of enforcing it — so the context fills and you get to compact by hand.

New optional `context` key in `profiles.conf` (tokens, e.g. `1000000`):

- Written through as `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and the
  `autoCompactWindow` setting, which is what actually arms auto-compact.
- At 1M or more, model ids (the pin and every picker row) also get Claude
  Code's `[1m]` tag appended — without it the compact window is clamped to
  the assumed 200k. The tag is client-side only; the API never sees it.
- Managed like the rest of the env: switching profiles (including back to
  OAuth) removes both keys when the target profile declares no `context`.

## 1.1.0

Renamed to **Skal Swap**. The plugin id is now `skal.swap` and the CLI is
`skal-swap`; the previous `skal.claude-code-switcher` / `skal-ccs` names are
gone. This is a breaking change and the plugin was never listed under the old
name, so there is no in-place upgrade path — reinstall, and move
`~/.config/skal.claude-code-switcher` to `~/.config/skal.swap` to keep your
profiles and OAuth bundles.

### Models come from the endpoint

- Each endpoint is asked what it serves instead of having model ids written
  into the profile. Discovery probes `/v1/models` on the base URL, then the
  OpenAI-compatible `/compatible-mode/v1/models` that providers such as
  Alibaba park the catalogue under. Cached for a day (`CCS_MODELS_TTL`), a
  stale list beats none, and `models_url` overrides the probe.
- The catalogue is written to `settings.json` as a `modelPicker` lineup, so
  `/model` moves between an endpoint's models inside a session. One profile is
  no longer one model.
- New commands: `skal-swap models [<id>] [--refresh|--json]` and
  `skal-swap use <id> --model <model-id>`, the latter remembered per profile.
- New profile keys: `model`, `models_url`, `behaves_as`.

### Only the URL and the key are required

- A profile needs `base_url` and `token` and nothing else. `name` falls back
  to the endpoint host, `model` to the newest chat model the endpoint reports,
  and `behaves_as` to `claude-sonnet-4-5` for any profile with a `base_url`
  (`CCS_BEHAVES_AS` moves that default). Everything else was already optional.
- Fixed: a profile without a `name` could be listed but not used. `name` was
  doubling as the existence check, so `use`, `models` and `oauth-add` all
  rejected a section that hadn't set one.
- Discovered catalogues are filtered to chat models — anything matching audio,
  image, video, speech, embedding or reranking is dropped, which keeps
  Alibaba's image and TTS ids out of the picker — then sorted newest first,
  preferring the full model over its `-flash`/`-mini`/`-lite` sibling when
  two share a release date. That ordering is also what picks the model when a
  profile doesn't name one.

### Fixes

- Model selection no longer goes through the `ANTHROPIC_DEFAULT_*` slot
  aliases. Those map the aliases but leave `settings.json`'s top-level `model`
  pin in charge, so a pin of `opus` followed you onto every endpoint and the
  gateway was asked for a model it does not serve. The switcher now owns that
  pin per profile and restores the previous one when you return to the OAuth
  profile.
- Selection is the `model` key rather than `ANTHROPIC_MODEL`: the environment
  variable outranks the key and would override anything picked with `/model`
  mid-session.
- `behaves_as` maps an endpoint's ids onto a model this Claude Code build
  knows. Without it an unrecognized id is treated as a current model and the
  request carries the full modern feature set — newer tool-schema fields,
  adaptive thinking, effort — which gateways that have not caught up reject
  with `400 Invalid API parameter`.
- `modelPicker` is emitted in the shape Claude Code validates: an object with
  an `options` array, not a bare array. The earlier shape was rejected at
  startup and silently ignored.
- Switching clears `clientDataCacheSlots` from `~/.claude.json`, so a model id
  resolved under one profile cannot be reused against another provider.
- `migrate-glm` and `init` no longer seed `ANTHROPIC_DEFAULT_*` model
  mappings into new profiles.

## 1.0.0

First release: profile switching for keys, endpoints and model mappings, a bar
widget with the active profile, multiple Claude OAuth logins, and per-account
usage readouts through ai-usagebar.
