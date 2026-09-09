# skal.claude-code-switcher

A menubar switcher for [Claude Code](https://claude.com/claude-code) API
profiles on [Omarchy](https://omarchy.org). Shows which key and endpoint
Claude Code is running on, and switches between any number of configured
profiles — API keys, Anthropic-compatible endpoints, model mappings, or back
to the official Claude OAuth login — from a popup in the bar.

## Why

Claude Code is still the best dev harness around — the agent loop, the tooling,
the ergonomics. But being married to one model or vendor is a choice we don't
want to make: we constantly run other models (GLM coding plans, other
Anthropic-compatible providers) *through* Claude Code. The friction was never
the models — it was the key juggling: hand-editing `settings.json`, keeping
model mappings straight, wondering which key is live. This plugin treats every
key/endpoint as a named profile and makes switching a menubar click, with each
key's usage right there so you know which plan to burn next.

The bar item shows the Claude logomark (tinted to your theme) with the active
profile name. Click for the profile picker, middle-click to quick-swap between
your two most-used profiles. Every switch announces itself with a toast.

## Features

- Bar widget with the active profile at a glance (logo + name, host, or icon
  only — your choice)
- Popup picker with the active profile marked and optional per-account usage
  readouts ([ai-usagebar](https://github.com/akitaonrails/ai-usagebar) when
  installed; z.ai accounts show session/weekly percentages)
- Any provider with an Anthropic-compatible endpoint (z.ai, proxies, gateways,
  …) alongside the official Anthropic API
- A token-less profile returns Claude Code to its normal `claude` OAuth login
- Clean env switching: applying a profile clears every managed
  `ANTHROPIC_*` key first, then writes the profile's — no stale model
  mappings or endpoints left behind
- `~/.claude/settings.json` is rewritten atomically and everything outside
  `env.ANTHROPIC_*` is untouched (file mode tightened to 600); Claude Code's
  cached model id (`clientDataCacheSlots` in `~/.claude.json`) is dropped so a
  stale Anthropic id can't leak onto a third-party endpoint
- Stays in sync no matter what changed the profile — menu, terminal CLI,
  keybinding, or a manual edit (file watchers + slow poll)
- **Quota/usage across the board** — progress bars and percentages per
  account, per key where the provider allows it (see below)
- Models discovered from each endpoint's own catalogue and offered in
  Claude Code's `/model` picker, so one profile isn't one model
- Companion CLI: `skal-ccs status | list | use <id> | models | swap | edit | init`

### Usage coverage

Per-key usage (add `usage = <vendor>` to a profile) works for **z.ai,
OpenRouter, DeepSeek, Kimi/Moonshot, Kilo, Novita, xAI (grok), MiniMax and
opencode zen** — each key is fetched under its own isolated account. For a
provider you only have one profile on, usage attaches automatically with no
marker at all. Claude OAuth usage follows the live login: the active OAuth
profile shows the session/weekly windows of whatever account is actually
logged in. Providers without a public usage API (Alibaba's token-plan
gateways publish none — no endpoint, no headers) show a console link
instead. All of this rides on
[ai-usagebar](https://github.com/akitaonrails/ai-usagebar) being installed;
without it the switcher works fine, just without usage readouts.

## Install

```bash
omarchy plugin add https://github.com/outcrop-labs/skal-claude-code-switcher.git --yes
omarchy plugin enable skal.claude-code-switcher --section left

# CLI on PATH (terminal use, keybindings, the Edit profiles menu entry):
ln -sfn ~/.config/omarchy/plugins/skal.claude-code-switcher/bin/skal-ccs ~/.local/bin/skal-ccs

# Create the profiles file with a commented example, then put your keys in it:
skal-ccs edit
```

Profiles live in `~/.config/skal.claude-code-switcher/profiles.conf` (chmod
600) — outside the plugin directory, so secrets never end up in a repo or an
update. The widget reads it on the fly; no shell restart needed.

Optional keybinding for a quick swap between the first two profiles (example
uses SUPER+ALT+K in `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + K", "Claude Code key swap", "skal-ccs swap")
```

## Uninstall

```bash
omarchy plugin disable skal.claude-code-switcher
omarchy plugin remove skal.claude-code-switcher --yes
rm -f ~/.local/bin/skal-ccs
# Save any keys you still need first, then:
rm -rf ~/.config/skal.claude-code-switcher
```

Remove the keybinding above if you added it.

## Dependencies

- `bash` + `jq` (the `skal-ccs` CLI; jq ships with Omarchy)
- Optional: `ai-usagebar` on PATH for usage readouts in the menu
- `omarchy-notification-send` (ships with Omarchy) for switch toasts

## Config

`~/.config/skal.claude-code-switcher/profiles.conf` — INI-style, one profile
per section (see `profiles.conf.example`):

```ini
[zai-plan-a]
name = Z.AI plan A
base_url = https://api.z.ai/api/anthropic
token = ...
model = glm-5.3
usage = zai

[anthropic-login]
name = Claude (OAuth)
```

`model` is the starting model for the endpoint; omit it and Claude Code picks
from the discovered list. Don't use the
`ANTHROPIC_DEFAULT_{SONNET,OPUS,HAIKU}_MODEL` aliases: they leave the
top-level `"model"` pin in `~/.claude/settings.json` in charge, so a pin like
`"opus"` follows you onto every endpoint and the gateway is asked for a model
it doesn't serve. The switcher sets that pin itself, and restores your
previous one when you switch back to the OAuth profile.

| key | meaning |
| --- | --- |
| `name` | label in the bar, menu, and toasts |
| `base_url` | Anthropic-compatible endpoint; omit for the official API |
| `token` | API token; omit to fall back to Claude Code's OAuth login |
| `model` | starting model id for this endpoint (optional; the rest of the lineup is discovered) |
| `models_url` | optional override for the model-catalogue URL, when probing doesn't find it |
| `env.<NAME>` | extra env written with the profile |
| `usage` | optional per-key usage marker (`zai`, `openrouter`, `deepseek`, `kimi`, `kilo`, `novita`, `moonshot`, `grok`, `minimax`, `opencode-go`) |
| `icon` | optional provider-mark override (`zai`, `openai`, `qwen`, …) |
| `oauth` | `true` for adopted OAuth-login profiles (see below) |

### Models per endpoint

Each endpoint is asked what it serves rather than having its models hardcoded.
`skal-ccs models` lists them, and every switch writes the lineup into
`modelPicker`, so `/model` moves between them inside a session:

```bash
skal-ccs models                     # models on the active profile (* = active)
skal-ccs models zai-plan-a --refresh
skal-ccs use zai-plan-a --model glm-5.3-flash   # remembered for that profile
```

Discovery probes the endpoint's own catalogue: `/v1/models` on the base URL
first, then the OpenAI-compatible `/compatible-mode/v1/models` several
providers park it under. Results are cached for a day (`CCS_MODELS_TTL`), a
stale list beats none, and `models_url` overrides the probe. An endpoint that
publishes nothing simply keeps the profile's `model`. Claude Code's own
`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` doesn't cover this case: it keeps
only model ids containing `claude` or `anthropic`.

Note that a catalogue may list non-chat models — Alibaba's token plan includes
image and audio ids — and they appear in the picker as published.

### Multiple Claude OAuth logins

Claude Code keeps a single OAuth session, but the switcher can juggle
several. Adopt the account you are currently logged into as a profile:

```bash
skal-ccs oauth-add work          # stores the live ~/.claude/.credentials.json + account
claude                           # /logout, then /login with the other account
skal-ccs oauth-add personal      # adopt the second one
```

Switching to an OAuth profile (from the bar menu or `skal-ccs use work`)
swaps that profile's stored credentials and account into place and clears
the API-key env overrides. Switching away syncs the live session —
including any token refreshes — back into the profile's store first. If
you log into a *different* account by hand while a profile is active, the
switcher detects the mismatch, skips the sync-back with a warning, and
expects you to adopt the new login with `oauth-add` rather than lose it.

Credential bundles live under
`~/.config/skal.claude-code-switcher/credentials/` (chmod 600, outside any
repo). As with key switches: switch while no claude sessions are running —
running sessions keep their in-memory tokens and would write them back on
exit.

### Alibaba Cloud token plans (Qwen, DeepSeek, …)

Alibaba Cloud's Model Studio token plans expose an Anthropic-compatible
gateway; a profile is just the endpoint plus the plan's model ids:

```ini
[alibaba-qwen]
name = Alibaba Qwen
base_url = https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic
token = sk-sp-…
model = qwen3.8-flash
```

One profile names one model; add a second profile against the same endpoint
and token to keep another of the plan's model ids a click away.

Use the regional host your key belongs to (`ap-southeast-1` above; the
pay-as-you-go Model Studio endpoint is `dashscope.aliyuncs.com/apps/anthropic`
or `dashscope-intl…` for international keys). The gateway is picky about
model ids and entitlements — a `Model not exist` response means the id is
wrong for that gateway, `Access to model denied` means the id exists but
your plan tier does not include it. A `icon = deepseek` style override picks
the row's provider mark when one plan serves several model families.

### Known providers

Any Anthropic-compatible endpoint works — the plugin is provider-agnostic.
These get their brand mark automatically from the endpoint host (override
with `icon =`); everyone else gets the neutral three-bar mark:

| Provider | Endpoint host | Kind |
| --- | --- | --- |
| Anthropic | `api.anthropic.com` (or OAuth login) | coding plans |
| Z.AI (GLM) | `api.z.ai`, `open.bigmodel.cn` | coding plans |
| Alibaba / Qwen | `*.aliyuncs.com`, token-plan `*.maas.aliyuncs.com` | coding plans + PAYG |
| Kimi (Moonshot) | `api.moonshot.ai` / `.cn` | coding plans |
| MiniMax | `api.minimax.io`, `api.minimaxi.com` | coding plans |
| Xiaomi MiMo | `api.xiaomimimo.com` | coding plans |
| StepFun | `api.stepfun.ai` / `.com` | coding plans + PAYG |
| xAI | `api.x.ai` | PAYG |
| DeepSeek | `api.deepseek.com` / `.cn` | PAYG |
| Mistral | `api.mistral.ai` | PAYG |
| Groq | `api.groq.com` | PAYG |
| Cerebras | `api.cerebras.ai` | PAYG |
| Google Gemini | `generativelanguage.googleapis.com` | PAYG |
| OpenAI | `api.openai.com` | PAYG |
| OpenRouter | `openrouter.ai` | aggregator |
| Kilo | `kilo.ai`, `api.kilo.ai` | aggregator |
| Novita | `api.novita.ai` | aggregator |
| GLama | `glama.ai` | aggregator |
| opencode zen | `opencode.ai` | aggregator |
| SiliconFlow | `api.siliconflow.com` / `.cn` | aggregator |
| Hugging Face | `api.huggingface.co` | aggregator |
| Ollama | `localhost:11434` | local |

Model mappings are per-profile `env.*` keys; a good maintained reference
for exact endpoint paths and current model ids is
[cc-compatible-models](https://github.com/Alorse/cc-compatible-models).

Bar widget settings (inline on the shell.json layout entry or via your bar's
settings UI): `icon` (`Logo` / `Glyph` / `None`), `labelStyle` (`Name` /
`Host` / `Icon`), `glyph` (Nerd Font glyph for `Glyph` mode and toasts).

**What this writes, by design and only when you ask it to:** `skal-ccs use` /
`swap` (from the menu, terminal, or a keybind) rewrite the managed
`ANTHROPIC_*` keys inside the `env` object of `~/.claude/settings.json`, and
set that file's top-level `model` and `modelPicker` for the endpoint you
switched to — `modelPicker` replaces the built-in lineup, so returning to the
OAuth profile removes it again and restores the `model` pin you had before
the first third-party switch. Nothing else in that file is modified. They
also drop the
`clientDataCacheSlots` key from `~/.claude.json` — Claude Code caches the
*resolved* model id there per entrypoint, keyed without regard to
`ANTHROPIC_BASE_URL`, so a slot filled under the OAuth profile otherwise
survives the switch and sends a literal Anthropic model id (`claude-sonnet-5`)
to your gateway, which rejects it with an invalid-parameter 400. It is a
cache: Claude Code repopulates it on next start, and nothing else in that file
is touched. Running claude sessions keep the previous key until restarted; the
toast reminds you.

## CLI

```
skal-ccs status [ --json ]   which profile is active (JSON drives the widget)
skal-ccs list                configured profiles
skal-ccs use <id>            switch  [--model <id>] pick the model too
skal-ccs models [<id>]       models the endpoint reports (* = active)
                             [--refresh] [--json]
skal-ccs swap                quick-toggle between the first two profiles
skal-ccs edit                open the profiles file in $EDITOR
skal-ccs init                write an example profiles file
skal-ccs usage --json        per-account usage from ai-usagebar, normalized
```

Tokens are always masked to their first 8 characters in output.

## Troubleshooting

- **Switched but Claude Code still uses the old key** — already-running
  sessions read env at startup; restart them.
- **`API Error: 400 … Invalid API parameter` right after switching to a
  non-Anthropic profile** — Claude Code cached the resolved model id from your
  previous profile and sent a literal Anthropic id (e.g. `claude-sonnet-5`) to
  a gateway that has no such model. `skal-ccs use` clears that cache on every
  switch; if you hit it on an older version, switch profiles again (or remove
  `clientDataCacheSlots` from `~/.claude.json`) and start a fresh session. Note
  it reproduces only in interactive sessions — `claude -p` reads a different
  cache slot.
- **Widget shows `…` or `custom`** — `…` means `skal-ccs status --json` failed
  (run it in a terminal to see why); `custom` means the active token matches
  no profile in profiles.conf.
- **Plugin widget fails to load after an in-place update** — clear the QML
  cache and restart the shell once:

  ```bash
  rm -rf "$HOME/.cache/quickshell/qmlcache" "$HOME/.cache/quickshell"/qtpipelinecache-*
  omarchy restart shell
  ```

## Credits

- Claude logomark from [simple-icons](https://simpleicons.org) (CC0).
- Built on the Omarchy shell plugin kit; sibling of
  [skal.bar](https://github.com/outcrop-labs/skal-bar).

## License

MIT — see [LICENSE](LICENSE).
