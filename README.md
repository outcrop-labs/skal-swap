# Skal Swap

Swap the model behind [Claude Code](https://claude.com/claude-code) from your
[Omarchy](https://omarchy.org) bar. Shows the key, endpoint and model you're
actually on. Click to change any of it.

Installs as the bar plugin `skal.swap`. That's it — nothing gets dropped onto
your PATH.

## Why

Claude Code is a great harness. The agent loop, the tooling, the ergonomics,
all of it. It also ships welded to one vendor, which is fine right up until
the moment you'd like to run something else through it.

Plenty of us already do, by hand. You know the routine: export
`ANTHROPIC_BASE_URL`, paste a key into `settings.json`, go digging for which
model ids that endpoint will actually answer to, then unpick the whole lot
when you want Claude back. Somewhere in there you lose track of which key is
live. It works fine! It's also tedious enough that most people wire it up
once and then never touch it again, which rather defeats the point of having
options.

So: this. Every key and endpoint is a profile. Switching is a click. The
models come from the provider instead of from your memory. The usage bars
tell you which plan you're closest to torching.

Mostly though, it's a laugh. Swapping the model underneath a harness you know
cold is a genuinely odd experience — same tools, same prompts, same loop,
different brain at the wheel. And because nothing else moved, you notice
everything. This one plans like an architect and writes code like it's 4am.
That one is blunt to the point of rude and never wastes a token. The cheap
one keeps quietly nailing refactors you'd have thrown the expensive model at.
Turns out "which model is best" is the wrong question and "best at what" is
the right one. Keep a few around. Use whichever suits the job.

The bar item shows the Claude logomark (tinted to your theme) and the active
profile. Click for the picker, middle-click to bounce between your two
most-used profiles. Every switch fires a toast so you know what just changed.

## Features

- Bar widget showing the active profile at a glance (logo + name, host, or
  just the icon)
- Popup picker with the active profile marked, plus per-account usage
  readouts if you have [ai-usagebar](https://github.com/akitaonrails/ai-usagebar)
  (z.ai accounts get session/weekly percentages)
- Works with any Anthropic-compatible endpoint — z.ai, proxies, gateways,
  whatever — alongside the official Anthropic API
- A profile with no token drops you back to your normal `claude` OAuth login
- Switching is clean: every managed `ANTHROPIC_*` key is cleared first, then
  the new profile's are written, so nothing stale survives the swap
- Models are pulled from each endpoint's own catalogue and handed to Claude
  Code's `/model` picker, so a profile isn't stuck on one model
- Keeps up no matter what changed the profile — the menu, a keybind, the
  bundled script, or you editing the file by hand
- **Usage bars across the board**, per account and per key where the provider
  allows it (details below)

### Usage coverage

Per-key usage (`usage = <vendor>` on a profile) works for **z.ai, OpenRouter,
DeepSeek, Kimi/Moonshot, Kilo, Novita, xAI (grok), MiniMax and opencode
zen** — each key gets fetched under its own account. If you've only got one
profile on a provider, usage attaches by itself and you can skip the marker.
Claude OAuth usage follows whichever account is actually logged in. Providers
with no public usage API get a console link instead — Alibaba's token-plan
gateways publish nothing at all, no endpoint, no headers, so a link is the
best anyone can do. All of this needs
[ai-usagebar](https://github.com/akitaonrails/ai-usagebar) installed; without
it everything else still works, you just don't get the bars.

## Install

```bash
omarchy plugin add https://github.com/outcrop-labs/skal-swap.git --yes
omarchy plugin enable skal.swap --section left
```

Then put your keys in:

```bash
~/.config/omarchy/plugins/skal.swap/bin/skal-swap edit
```

Profiles live in `~/.config/skal.swap/profiles.conf` (chmod 600), outside the
plugin directory, so your keys don't end up in a repo or get blown away by an
update. The widget re-reads it on the fly.

The plugin ships a script at `bin/skal-swap` — it's what the widget calls, and
you can run it directly as above. If you'd rather have it on your PATH, that's
your call, not something the install does to you:

```bash
ln -sfn ~/.config/omarchy/plugins/skal.swap/bin/skal-swap ~/.local/bin/skal-swap
```

Optional keybind to bounce between your first two profiles (SUPER+ALT+K, in
`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + K", "Claude Code key swap", "skal-swap swap")
```

## Uninstall

```bash
omarchy plugin disable skal.swap
omarchy plugin remove skal.swap --yes
rm -f ~/.local/bin/skal-swap        # if you symlinked it
# Grab any keys you still want first, then:
rm -rf ~/.config/skal.swap
```

And remove the keybind if you added one.

## Dependencies

- `bash` + `jq` (jq ships with Omarchy, so probably nothing to do here)
- `omarchy-notification-send` for the toasts (also ships with Omarchy)
- Optional: `ai-usagebar` on PATH, for the usage readouts

## Config

`~/.config/skal.swap/profiles.conf` — INI-ish, one profile per section (see
`profiles.conf.example`):

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

`model` is just where you start; leave it out and Claude Code picks from
whatever the endpoint reports. Don't reach for the
`ANTHROPIC_DEFAULT_{SONNET,OPUS,HAIKU}_MODEL` variables — they map the
aliases but leave the top-level `"model"` pin in `~/.claude/settings.json`
running the show, so a pin of `"opus"` cheerfully follows you onto a GLM
endpoint and asks it for Opus. Skal Swap owns that pin instead, and puts your
old one back when you return to the OAuth profile.

| key | meaning |
| --- | --- |
| `name` | label in the bar, menu, and toasts |
| `base_url` | Anthropic-compatible endpoint; omit for the official API |
| `token` | API token; omit to fall back to Claude Code's OAuth login |
| `model` | starting model id for this endpoint (optional; the rest of the lineup is discovered) |
| `models_url` | optional override for the model-catalogue URL, when probing doesn't find it |
| `behaves_as` | id of a model this Claude Code build knows, whose client-side handling (prompt profile, capability and effort defaults) applies to this endpoint's ids |
| `env.<NAME>` | extra env written with the profile |
| `usage` | optional per-key usage marker (`zai`, `openrouter`, `deepseek`, `kimi`, `kilo`, `novita`, `moonshot`, `grok`, `minimax`, `opencode-go`) |
| `icon` | optional provider-mark override (`zai`, `openai`, `qwen`, …) |
| `oauth` | `true` for adopted OAuth-login profiles (see below) |

### Models per endpoint

Nobody wants to maintain a hardcoded list of model ids, so we don't. Each
endpoint gets asked what it serves, and the answer goes into `modelPicker`,
which means `/model` swaps between them without leaving your session:

```bash
skal-swap models                     # models on the active profile (* = active)
skal-swap models zai-plan-a --refresh
skal-swap use zai-plan-a --model glm-5.3-flash   # remembered for that profile
```

Discovery tries `/v1/models` on the base URL first, then the OpenAI-compatible
`/compatible-mode/v1/models` that a few providers park it under. Cached for a
day (`CCS_MODELS_TTL`), a stale list beats no list, and `models_url` overrides
the guessing if your provider hides it somewhere else entirely. An endpoint
that publishes nothing just keeps whatever `model` you set. Claude Code has
its own `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`, which is no use here: it
throws away any model id that doesn't contain `claude` or `anthropic`, which
is to say, all of them.

Catalogues aren't always tidy — Alibaba's token plan lists image and audio
models too, and they show up in the picker exactly as published.

`behaves_as` looks like a footnote and isn't. Hand Claude Code a model id it's
never heard of and it assumes the best: current model, so it sends the full
modern kit — new tool-schema fields, adaptive thinking, effort — and a gateway
that hasn't caught up throws the whole request back at you. Point `behaves_as`
at a model your Claude Code build does know (`claude-sonnet-4-5` is a safe
floor) and it uses that model's defaults instead. The picker also sets
`replaceBuiltInOptions`, because listing Opus on a GLM endpoint helps nobody.

### Multiple Claude OAuth logins

Claude Code holds one OAuth session at a time. Skal Swap will juggle several
anyway. Adopt whichever account you're logged into right now:

```bash
skal-swap oauth-add work          # stores the live ~/.claude/.credentials.json + account
claude                            # /logout, then /login as the other one
skal-swap oauth-add personal      # adopt that one too
```

Switching to an OAuth profile swaps its stored credentials into place and
clears the API-key overrides. Switching away syncs the live session back
first, token refreshes included, so nothing gets lost. Log into a *different*
account by hand while a profile is active and it'll spot the mismatch, refuse
to overwrite the stored one, and tell you to `oauth-add` the new login rather
than quietly clobbering it.

Bundles live in `~/.config/skal.swap/credentials/` (chmod 600, outside any
repo). Same warning as with keys: swap while no claude sessions are running.
A live session is sitting on its old tokens and will write them back when it
exits.

### Alibaba Cloud token plans (Qwen, DeepSeek, …)

Alibaba's Model Studio token plans speak Anthropic, so a profile is just the
endpoint and the key:

```ini
[alibaba-qwen]
name = Alibaba Qwen
base_url = https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic
token = sk-sp-…
model = qwen3.8-flash
```

`model` only picks a starting point — the rest of the plan (Qwen, DeepSeek and
GLM builds, plus the image and audio ones) gets discovered and lands in the
picker. This gateway keeps its catalogue at `/compatible-mode/v1/models`
instead of under the Anthropic path, which the probe already handles.

Use the regional host your key belongs to (`ap-southeast-1` above; pay-as-you-go
Model Studio is `dashscope.aliyuncs.com/apps/anthropic`, or `dashscope-intl…`
for international keys). The gateway is fussy about ids and entitlements:
`Model not exist` means wrong id for that host, `Access to model denied` means
the id is real but your tier isn't invited. `icon = deepseek` and friends fix
the row's badge when one plan serves several model families.

### Known providers

Any Anthropic-compatible endpoint works — the plugin doesn't care who's on the
other end. These get their brand mark picked automatically from the host
(override with `icon =`); everyone else gets the neutral three-bar mark:

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

If you need a reference for exact endpoint paths and current model ids,
[cc-compatible-models](https://github.com/Alorse/cc-compatible-models) is
well maintained.

Widget settings (inline on the shell.json entry, or through your bar's
settings UI): `icon` (`Logo` / `Glyph` / `None`), `labelStyle` (`Name` /
`Host` / `Icon`), `glyph` (Nerd Font glyph for `Glyph` mode and toasts).

### What it writes

Only when you actually pick a profile. A switch rewrites the managed
`ANTHROPIC_*` keys inside the `env` object of `~/.claude/settings.json`, and
sets that file's top-level `model` and `modelPicker` for wherever you're
heading. `modelPicker` replaces the built-in lineup, so going back to the
OAuth profile removes it and restores the `model` pin you had before you
started messing about. Nothing else in that file gets touched.

It also drops `clientDataCacheSlots` from `~/.claude.json`. That's a Claude
Code cache of the resolved model id, and it doesn't care which endpoint you're
pointed at, so a slot filled up under one provider can get handed to the next
one. It's a cache; Claude Code rebuilds it on the next start.

Sessions already running keep the old key until you restart them. The toast
says as much.

## The bundled script

`bin/skal-swap` is what the widget shells out to, and it's a perfectly good
way to drive things from a terminal or a keybind:

```
skal-swap status [ --json ]   which profile is active (JSON drives the widget)
skal-swap list                configured profiles
skal-swap use <id>            switch  [--model <id>] pick the model too
skal-swap models [<id>]       models the endpoint reports (* = active)
                              [--refresh] [--json]
skal-swap swap                quick-toggle between the first two profiles
skal-swap edit                open the profiles file in $EDITOR
skal-swap init                write an example profiles file
skal-swap usage --json        per-account usage from ai-usagebar, normalized
```

Tokens are always masked to their first 8 characters.

## Roadmap

- **One Claude Code per provider, in containers.** Right now a switch is
  machine-wide, because `settings.json` is global — every session follows the
  active profile and you get exactly one provider at a time. The plan is
  per-provider instances running side by side, each pinned to its own
  endpoint, key and model, so a cheap plan can chew through something long
  and boring while a better one handles the work you're watching.
- **The Skalswap CLI** will drive those instances. Separate project, entirely
  optional, and not written yet. It'll ship `skal-swap` as a superset of the
  script bundled here, so installing it upgrades the command rather than
  leaving two confusingly similar binaries on your PATH. This plugin won't
  ever depend on it: if it's there, the bar grows some extra tricks; if it
  isn't, everything above works exactly as written.
- **A UI for adding providers**, so a new endpoint and key is a dialog instead
  of a text file.

## Troubleshooting

- **Switched, but Claude Code is still on the old key.** Running sessions read
  their env at startup. Restart them.
- **`API Error: 400 … Invalid API parameter` on a non-Anthropic profile.**
  You're sending the endpoint something it doesn't implement. Claude Code sees
  a model id it doesn't recognise, assumes it's current, and includes the full
  modern feature set — new tool-schema fields, adaptive thinking, effort — and
  the gateway rejects the lot. Set `behaves_as` on the profile to a model your
  build does know (`claude-sonnet-4-5` is a sensible floor; adaptive thinking
  starts at 4.6), switch again, start a fresh session. If a specific beta is
  the culprit, `env.CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = 1` on the profile
  is the bigger hammer. Fair warning: this only shows up in interactive
  sessions. `claude -p` sends a smaller request and sails right through, which
  is a fun way to lose an afternoon.
- **Widget shows `…` or `custom`.** `…` means `skal-swap status --json` fell
  over — run it in a terminal and it'll tell you why. `custom` means the token
  in play doesn't match any profile you've configured.
- **Widget won't load after an in-place update.** Clear the QML cache and
  restart the shell:

  ```bash
  rm -rf "$HOME/.cache/quickshell/qmlcache" "$HOME/.cache/quickshell"/qtpipelinecache-*
  omarchy restart shell
  ```

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).

## Credits

- Claude logomark from [simple-icons](https://simpleicons.org) (CC0).
- Built on the Omarchy shell plugin kit; sibling of
  [skal.bar](https://github.com/outcrop-labs/skal-bar).

## License

MIT — see [LICENSE](LICENSE).
