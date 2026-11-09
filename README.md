# Skål Swap

Swap the model behind [Claude Code](https://claude.com/claude-code) from your
[Omarchy](https://omarchy.org) bar. Shows the key, endpoint and model you're
actually on. Click to change any of it.

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

It's also just weird, in a good way. Same Claude-y feel, different brains that
reason through things in unique ways. Nothing else changed, so the differences
show up pretty quickly: one of them one-shots a refactor you'd assumed needed
Fable, another writes something you'd never ship with total confidence in a
Bob Rossian happy-accidents fashion. After a week of that you stop asking
which model is best and start keeping a few around for different jobs.

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
Every Claude login shows its own session and weekly limits, read straight
from the endpoint behind Claude Code's `/usage`, whichever one the machine is
on. Providers
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
base_url = https://api.z.ai/api/anthropic
token = ...

[anthropic-login]
```

That's a complete, working profile. **`base_url` and `token` are the only
things you have to supply**; everything else is optional and gets worked out
for you. The label falls back to the endpoint host, the model to the newest
one the endpoint reports, and the capability floor to something that won't
get your requests rejected. A section with neither key is your Claude OAuth
login.

Fill in more when you want to override any of that:

```ini
[zai-plan-a]
name = Z.AI plan A
base_url = https://api.z.ai/api/anthropic
token = ...
model = glm-5.3
usage = zai
```

Don't reach for the
`ANTHROPIC_DEFAULT_{SONNET,OPUS,HAIKU}_MODEL` variables — they map the
aliases but leave the top-level `"model"` pin in `~/.claude/settings.json`
running the show, so a pin of `"opus"` cheerfully follows you onto a GLM
endpoint and asks it for Opus. Skal Swap owns that pin instead, and puts your
old one back when you return to the OAuth profile.

| key | meaning |
| --- | --- |
| `base_url` | **required** for a provider profile; omit it and you get the official API / OAuth login |
| `token` | **required** for a provider profile; omit to fall back to Claude Code's OAuth login |
| `name` | optional label for the bar, menu and toasts; defaults to the endpoint host |
| `model` | optional starting model; defaults to the newest chat model the endpoint reports |
| `models_url` | optional override for the model-catalogue URL, if the probe can't find it |
| `behaves_as` | optional capability floor — id of a model your Claude Code build knows, whose prompt profile, capability and effort defaults get used. Defaults to `claude-sonnet-4-5` for any profile with a `base_url` |
| `context` | optional context window of the endpoint's models, in tokens (e.g. `1000000`). Declares it to Claude Code so auto-compact actually fires; see below |
| `max_output` | optional override for the longest single response, in tokens. Read off the endpoint's catalogue when it reports one, so set this only when the catalogue is silent or wrong; see below |
| `env.<NAME>` | extra env written with the profile |
| `usage` | optional per-key usage marker (`zai`, `openrouter`, `deepseek`, `kimi`, `kilo`, `novita`, `moonshot`, `grok`, `minimax`, `opencode-go`) |
| `icon` | optional provider-mark override (`zai`, `openai`, `qwen`, …) |
| `oauth` | `true` marks a Claude login; implied by no `base_url` and no `token` (see below) |

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

Catalogues aren't always tidy. Alibaba's token plan cheerfully lists image
and audio models alongside the chat ones, so anything that looks like audio,
image, video, speech, embedding or reranking gets dropped before it reaches
the picker. What's left is sorted newest first, and where two models share a
release date the full-fat one wins over the `-flash`/`-mini`/`-lite` variant,
which is also how the automatic pick gets chosen when you haven't set
`model`.

`behaves_as` looks like a footnote and isn't. Hand Claude Code a model id it's
never heard of and it assumes the best: current model, so it sends the full
modern kit — new tool-schema fields, adaptive thinking, effort — and a gateway
that hasn't caught up throws the whole request back at you. So every profile
with a `base_url` gets `claude-sonnet-4-5` as a floor unless you say
otherwise, which is why you don't have to think about this. Set `behaves_as`
yourself if your endpoint keeps up with Anthropic and you want the newer
behaviour, or `CCS_BEHAVES_AS` to move the default. The picker also sets
`replaceBuiltInOptions`, because listing Opus on a GLM endpoint helps
nobody.

Then there's the context window, which is its own adventure. Give Claude Code
an id it's never heard of and it quietly assumes 200k — and then only *warns*
about that number instead of enforcing it, which means auto-compact never
arms and you get to run `/compact` by hand like an animal. `context` fixes
that: the number is declared via `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and
`autoCompactWindow`, and compaction happens near it like Claude intended.
One quirk to know about: the compact window is clamped to the *believed*
window, which tops out at 200k unless the model id carries a `[1m]` tag. So
for a 1M endpoint (Z.ai's current GLM generation, say) set `context = 1000000`
and the tag gets appended to the pin and every picker row for you — the API
never sees it. Only set `context` when the endpoint's models share a window;
a profile serving both a 128k veteran and a 1M flagship wants two profiles.

The other end of the same problem is the *output* cap. Claude Code will only
let a single response run to 32000 tokens, and when a model wants to write
more you get `API Error: Claude's response exceeded the 32000 output token
maximum` and a half-finished file. Plenty of models go a lot further, so the
real ceiling gets declared as `CLAUDE_CODE_MAX_OUTPUT_TOKENS`.

Mostly you don't have to look the number up. The same catalogue that fills the
model picker often reports it, and whichever model the profile is pinned to
decides the number, so pinning a smaller sibling lowers it again on the next
switch. Anthropic's catalogue calls it `max_tokens` (next to
`max_input_tokens` for the window), OpenRouter calls it
`top_provider.max_completion_tokens`, others call it `max_output_tokens`.
This covers the OAuth profile too, where the pin is Claude Code's own and
usually an alias: `opus` resolves to the newest Opus the catalogue lists, and
that model's cap is the one written.

Two things to know. First, a fair few OpenAI-shaped listings reuse
`max_tokens` for the *context* length, so a bare `max_tokens` is only believed
when a separate input or context field is there to tell the two apart, and a
figure equal to that window is thrown away as the same mislabelling. Second,
plenty of endpoints (Z.ai and Alibaba's token-plan gateway among them) report
no limits whatsoever, and there the 32000 default stands until you say
otherwise. That is what `max_output` is for: it always wins, catalogue or no
catalogue.

Catalogue responses are capped at 4 MiB (`CCS_MODELS_MAX_BYTES` if you ever
need to move it) and timed out at 10 seconds. Over either limit the endpoint
is skipped rather than trusted, and the profile switches on whatever `model`
it has configured.

### Several Claude plans, side by side

Each Claude login gets its own Claude Code config dir under
`~/.local/share/skal.swap/homes/<id>`. That's what lets two plans run at the
same time: `skal-swap run <id>` starts claude with `CLAUDE_CONFIG_DIR` pointed
at that profile's dir, and nothing else on the machine moves. Everything else
in `~/.claude` (projects, history, skills, plugins, hooks, `CLAUDE.md`) is
symlinked in, so every plan shares the same memory and `/resume` works across
them. Only the login, `settings.json` and a little account-scoped state stay
separate.

```bash
skal-swap login max --name "Claude Max"   # browser login, straight into its own dir
skal-swap login pro --name "Claude Pro"   # and another
skal-swap run pro                         # claude on Pro, while Max keeps going elsewhere
skal-swap run pro -- --resume             # anything after -- goes to claude
skal-swap run -y pro                      # with --dangerously-skip-permissions
skal-swap use max                         # or make one the machine's default
```

A section with no `base_url` and no `token` is a Claude login (`oauth = true`
says so explicitly). `run` works on provider profiles too, so a z.ai session
can sit next to a Claude one.

A login lives in exactly one place at a time and never gets copied. OAuth
refresh tokens rotate, so two copies refreshing on their own end with one of
them dead. `use` moves a login from its dir into `~/.claude`, after moving
whatever login was there back to its owner's dir. Ownership goes by account
uuid, so a manual `/login` doesn't confuse it, and a login nobody has claimed
yet goes to the first login profile that hasn't got one. The profile's
`settings.json` is rebuilt from `~/.claude/settings.json` on every launch, so
your settings reach every plan but a z.ai switch never leaks into a Claude one.
Anything you change with `/config` inside a `run` session lands in that copy
and is gone next launch. Change `~/.claude/settings.json` instead.

Same warning as with keys: a running session holds its tokens in memory and
writes refreshed ones back where it started, so restart sessions after moving
a login with `use`. The CLI tells you when there are any.

Upgrading from the old bundle store (`~/.config/skal.swap/credentials/<id>.json`)
needs nothing: each bundle moves into its profile's dir the first time that
profile is used, and the file is renamed `.imported`.

### Other machines

List them in `~/.config/skal.swap/hosts.conf` and the popup grows a section
per machine, with the same rows, plan badges, session counts and usage bars:

```ini
# name = ssh destination
devbox = outcrop-labs
```

```bash
skal-swap push devbox                  # install this CLI there (needs jq + curl)
skal-swap @devbox login max            # log a plan in on that machine
skal-swap @devbox run max              # claude there, in this terminal
skal-swap @devbox use max              # switch that machine
```

Every machine keeps its own profiles and its own logins. Credentials never
travel between machines, because a refresh on one would knock the other out;
log each plan in on each machine instead (`push --profiles` copies your
provider keys over when the host has no `profiles.conf` yet). `run`, `login`
and `edit` get a terminal and a login shell on the far side, so claude starts
with the same environment as a session opened by hand.

### herdr

With [herdr](https://herdr.dev) installed, every row gets a second button
that opens a herdr tab running claude on that profile, on that row's machine,
and brings your herdr window up. It goes through `herdr agent start`, so
herdr tracks it as a claude agent like any other (named after the profile,
`claude-pro`, `claude-pro-2`, ...). Right-click either launch button to skip
permission prompts.

```bash
skal-swap herdr claude-pro                    # tab in the focused herdr workspace
skal-swap herdr -y claude-pro --cwd ~/code/x  # skip permissions, start somewhere else
skal-swap herdr claude-pro --workspace        # its own workspace instead
skal-swap @devbox herdr claude-pro            # on the devbox's herdr server
```

A remote tab shows up in your local herdr under that saved SSH machine.

### Setting up a new box

`sync` brings another machine up to this one, and is safe to run again
whenever your desktop setup changes:

```bash
skal-swap sync newbox --dest jon@newbox      # first time: adds it to hosts.conf
skal-swap sync devbox                        # later: just refresh
```

It installs this CLI there, sets herdr up (`herdr machine add` when the machine
isn't saved yet, which installs herdr on the far side), copies your herdr
`config.toml` (a different one there is kept as a timestamped backup, and a
running server reloads), and installs the herdr integrations you have here
for every agent that box has actually run. Last, it lists the Claude plans
that still need a `login` there. Provider keys come along only with
`--profiles`, and Claude logins never do.

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
skal-swap usage --json        per-account usage (ai-usagebar + each Claude login)
skal-swap run <id> [-- args]  claude on a profile without switching the machine
                              [-y|--skip-permissions] skips permission prompts
skal-swap login [<id>]        log a Claude plan into a profile  [--name N] [--email E]
skal-swap oauth-add <id>      claim the login already in ~/.claude as a profile
skal-swap hosts [--json]      machines from hosts.conf
skal-swap @<host> <cmd...>    any command on another machine
skal-swap push <host>         install this CLI on a host  [--profiles]
skal-swap sync <host>         bring a machine up to this one (CLI, herdr setup)
                              [--dest user@host] [--profiles] [--no-herdr]
skal-swap herdr [-y] <id>     a herdr tab running claude on a profile
                              [--cwd DIR] [--workspace] [--no-focus] [--session S]
skal-swap fleet --json        this machine plus every host, for the widget
```

Tokens are always masked to their first 8 characters.

## Roadmap

- **Containers per provider.** `run` already gives each profile its own
  config dir, so plans and providers run side by side. Containers would add
  isolation on top: pinned tool versions, a separate filesystem view.
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
