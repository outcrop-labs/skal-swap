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
  `env.ANTHROPIC_*` is untouched (file mode tightened to 600)
- Stays in sync no matter what changed the profile — menu, terminal CLI,
  keybinding, or a manual edit (file watchers + slow poll)
- Companion CLI: `skal-ccs status | list | use <id> | swap | edit | init`

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
usage = zai
env.ANTHROPIC_DEFAULT_SONNET_MODEL = glm-5.3

[anthropic-login]
name = Claude (OAuth)
```

| key | meaning |
| --- | --- |
| `name` | label in the bar, menu, and toasts |
| `base_url` | Anthropic-compatible endpoint; omit for the official API |
| `token` | API token; omit to fall back to Claude Code's OAuth login |
| `env.<NAME>` | extra env written with the profile (e.g. model mappings) |
| `usage` | optional account marker for usage display (`zai`) |
| `icon` | optional provider-mark override (`zai`, `openai`, `qwen`, …) |
| `oauth` | `true` for adopted OAuth-login profiles (see below) |

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
env.ANTHROPIC_DEFAULT_SONNET_MODEL = qwen3.8-flash
env.ANTHROPIC_DEFAULT_OPUS_MODEL = qwen3.8-max
env.ANTHROPIC_DEFAULT_HAIKU_MODEL = qwen3.8-flash
```

Use the regional host your key belongs to (`ap-southeast-1` above; the
pay-as-you-go Model Studio endpoint is `dashscope.aliyuncs.com/apps/anthropic`
or `dashscope-intl…` for international keys). The gateway is picky about
model ids and entitlements — a `Model not exist` response means the id is
wrong for that gateway, `Access to model denied` means the id exists but
your plan tier does not include it. A `icon = deepseek` style override picks
the row's provider mark when one plan serves several model families.

Bar widget settings (inline on the shell.json layout entry or via your bar's
settings UI): `icon` (`Logo` / `Glyph` / `None`), `labelStyle` (`Name` /
`Host` / `Icon`), `glyph` (Nerd Font glyph for `Glyph` mode and toasts).

**What this writes, by design and only when you ask it to:** `skal-ccs use` /
`swap` (from the menu, terminal, or a keybind) rewrite the managed
`ANTHROPIC_*` keys inside the `env` object of `~/.claude/settings.json`.
Nothing else in that file — and no other file — is modified. Running claude
sessions keep the previous key until restarted; the toast reminds you.

## CLI

```
skal-ccs status [ --json ]   which profile is active (JSON drives the widget)
skal-ccs list                configured profiles
skal-ccs use <id>            switch
skal-ccs swap                quick-toggle between the first two profiles
skal-ccs edit                open the profiles file in $EDITOR
skal-ccs init                write an example profiles file
skal-ccs usage --json        per-account usage from ai-usagebar, normalized
```

Tokens are always masked to their first 8 characters in output.

## Troubleshooting

- **Switched but Claude Code still uses the old key** — already-running
  sessions read env at startup; restart them.
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
