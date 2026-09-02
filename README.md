# G15 — Omarchy bar plugin

Dell G15 (5520) CPU/GPU temperatures and fan rpm in the [Omarchy](https://omarchy.org)
bar, with a panel for the two things you would otherwise open a terminal for:
the power mode and the RGB keyboard backlight.

- **Bar:** `󰍛 54°  󰢮 53°`, tooltip with both fan speeds and the current power mode.
- **Panel (left click):** temperature meters, power-mode chips
  (quiet / balanced / performance / G-Mode), a fan-boost slider, and the full
  keyboard backlight:
  brightness, effect (static / pulse / morph / cycle / rainbow), speed, and the
  effect's color list — click a swatch for an HSV picker with presets, a hex
  field, and a screen eyedropper. `+` / `−` grow and shrink the list within the
  limits the firmware fixes per effect (cycle and rainbow take up to 8).
- **Right click:** opens the `g15` TUI, for a keyboard-driven version of the
  same controls.

## Requires

The [`g15` CLI](https://github.com/andeen171/g15-cli), **0.3.1 or newer**, on
`PATH` (`yay -S g15-cli`). The version is checked at every poll — `g15 status`
reports it — and below 0.3.1 the power and fan controls disable themselves and
say so, because the privilege narrowing described under
[Privileges](#privileges) lives in the CLI. The widget only ever runs:

| Action | Command |
|---|---|
| poll | `g15 status` |
| power mode | `pkexec /usr/bin/g15 power <mode>` |
| fan boost | `pkexec /usr/bin/g15 fan boost <0-100>` |
| brightness | `g15 led brightness <0-100>` |
| effect | `g15 led effect <name>` |
| speed | `g15 led speed <1-10>` |
| colors | `g15 led colors RRGGBB[,RRGGBB...]` |
| eyedropper | `hyprpicker --format=hex` |

`hyprpicker` is optional — without it the picker's *Screen* button does
nothing, and everything else still works.

Polling reads hwmon, the alienware-wmi driver's platform profile, and
`~/.config/g15/state` — never the USB LED device, which must not be opened
concurrently.

## Install

```sh
omarchy plugin add https://github.com/andeen171/omarchy-g15.git --enable
```

Then place it with `omarchy plugin enable io.github.andeen171.g15 left` (or
`right`/`center`), or from Setup > Plugins.

## Removing

```sh
omarchy plugin disable io.github.andeen171.g15
rm -rf ~/.config/omarchy/plugins/io.github.andeen171.g15
omarchy restart shell
```

Nothing is left behind outside that directory: the plugin's own settings live
in the widget's `~/.config/omarchy/shell.json` entry, which `disable` removes,
and it never writes anywhere else. The `g15` CLI, its udev rule and its polkit
action are the CLI package's, and stay until you uninstall that.

## Privileges

Reading needs nothing. Temperatures, fan speeds and the fan boost come from
hwmon; the power mode comes from the alienware-wmi driver's platform profile,
so it stays right even when something other than this widget changes it. Only
the backlight's own settings come from `~/.config/g15/state`. LED writes go
over USB and need only the udev rule the CLI ships.

**Power modes and fan boost need root** (they go through the `acpi_call` WMI),
so those two controls run through `pkexec`. The Omarchy shell is a polkit
agent, so that surfaces as its own password dialog — nothing has to be
whitelisted in sudoers, and the authorization is asked for at the moment it is
used rather than granted forever.

Three things keep that grant as small as the two operations above:

- **The wrapper and the target are pinned, not settings.** The widget runs
  `pkexec` on the absolute path `/usr/bin/g15` — the same path the polkit action
  names, owned by the `g15-cli` package. Neither half is configurable, so no
  edit to the bar's config can redirect a privileged call at another binary.
  Wanting `doas` instead means editing `rootPrefix` in `Panel.qml`.
- **The CLI refuses the rest of itself.** polkit pins an executable but cannot
  filter its arguments, so `g15` narrows the grant from the inside: when it sees
  `PKEXEC_UID` it runs `power <mode>` and `fan boost <0-100>` and nothing else.
  `sudo g15 …` and a root shell are unaffected. This is what the 0.3.1 floor is
  for; the widget will not use the privileged path without it.
- **Nothing is retained.** The polkit action is `auth_admin`, not
  `auth_admin_keep`, so every privileged call authenticates. Dragging the fan
  slider asks again; that is the trade for never leaving a live authorization
  sitting around.

Check the action arrived:

```sh
pkaction --action-id org.andeen171.g15.control --verbose
```

Without it `pkexec` still works, falling back to
`org.freedesktop.policykit.exec` — which names the binary rather than the
operation. The CLI-side narrowing above applies either way.

If you built the CLI yourself instead of installing the package, install the
action by hand from the CLI repo:

```sh
sudo install -Dm644 org.andeen171.g15.policy \
  /usr/share/polkit-1/actions/org.andeen171.g15.policy
```

Delete that hand-installed copy before you ever install the `g15-cli` package.
pacman will not overwrite a file no package owns, and the upgrade fails with
`org.andeen171.g15.policy exists in filesystem`.

If a privileged call fails, the control snaps back to the real value on the
next poll.

## Developing

Edits to a plugin's QML are **not** picked up by a running shell, whatever
`omarchy-shell shell rescanPlugins` and the plugin's own reload log line
suggest — neither a rescan nor a disable/enable cycle rebuilds the loaded
component. After editing, run:

```sh
omarchy restart shell
omarchy plugin validate ~/.config/omarchy/plugins/io.github.andeen171.g15
qmllint -I /usr/share/omarchy/shell Panel.qml
node Model.test.js
qs log -p /usr/share/omarchy/shell --tail 100   # QML errors land here
```

`omarchy-shell shell summon io.github.andeen171.g15 '{}'` opens the panel
without clicking the bar, which is handy for screenshotting a state.

## History

This plugin was developed inside the
[g15-cli](https://github.com/andeen171/g15-cli) repo, under `omarchy-plugin/`,
until the CLI contract it depends on (`g15 status`, `g15 led effect`, …)
settled. `git subtree split` moved it here with that history intact, so the
commits below the split still describe the same files.

`Widget.qml` (plugin `andeen171.g15`, g15-cli 0.2.0) was the first version: a
`BarWidget` that polled `g15 waybar` for a text label and ran the TUI on click,
a straight port of the Waybar custom module Omarchy 3 used before the shell
replaced Waybar. It is gone from the working tree — `git show <ref>:Widget.qml`
— because `Panel.qml` is a superset: same readout, same click-to-TUI (now on
right click), plus the controls. It stays in the history as the minimal example
of a `bar-widget` plugin, and the plain `shell.json` command-module fallback
for it is still documented in the
[CLI's README](https://github.com/andeen171/g15-cli#readme).

## License

MIT — see LICENSE.
