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

The [`g15` CLI](https://github.com/andeen171/g15-cli) on `PATH` (`yay -S g15`).
The widget only ever runs:

| Action | Command |
|---|---|
| poll | `g15 status` |
| power mode | `pkexec /usr/bin/g15 power <mode>` (configurable) |
| fan boost | `pkexec /usr/bin/g15 fan boost <0-100>` (same setting) |
| brightness | `g15 led brightness <0-100>` |
| effect | `g15 led effect <name>` |
| speed | `g15 led speed <1-10>` |
| colors | `g15 led colors RRGGBB[,RRGGBB...]` |
| eyedropper | `hyprpicker --format=hex` |

`hyprpicker` is optional — without it the picker's *Screen* button does
nothing, and everything else still works.

Polling reads hwmon and `~/.config/g15/state` only — never the USB LED device,
which must not be opened concurrently.

## Install

This plugin lives in a subdirectory of the [g15-cli](https://github.com/andeen171/g15-cli)
repo, so `omarchy plugin add <repo-url>` does **not** work on it — that command
expects the repository root to be the plugin. Install by copy (the shell only
loads plugins from `~/.config/omarchy/plugins/`, and refuses symlinked plugin
directories):

```sh
git clone https://github.com/andeen171/g15-cli.git
cp -r g15-cli/omarchy-plugin ~/.config/omarchy/plugins/io.github.andeen171.g15
omarchy plugin validate ~/.config/omarchy/plugins/io.github.andeen171.g15
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.andeen171.g15 left
```

Because it is a copy, `git pull` does not update the widget — re-run the `cp`
and `rescanPlugins` after pulling.

## Privileges

Reading needs nothing — temperatures, fan speeds **and the current fan boost**
all come from hwmon, and the rest from `~/.config/g15/state`. LED writes go
over USB and need only the udev rule the CLI ships.

**Power modes and fan boost need root** (they go through the `acpi_call` WMI),
so those two controls run through `pkexec`. The Omarchy shell is a polkit
agent, so that surfaces as its own password dialog — nothing has to be
whitelisted in sudoers, and the authorization is asked for at the moment it is
used rather than granted forever.

Install the action the CLI ships (the `g15-cli` package does this for you) so
the prompt names what it is about to do and caches for a few minutes instead of
asking once per slider drag:

```sh
sudo install -Dm644 org.andeen171.g15.policy \
  /usr/share/polkit-1/actions/org.andeen171.g15.policy
pkaction --action-id org.andeen171.g15.control --verbose
```

Without it `pkexec` still works, falling back to
`org.freedesktop.policykit.exec` — which prompts every single time and names
the binary rather than the operation.

Prefer a passwordless setup? Point the widget's `rootCommand` setting at
`sudo -n g15` and add the sudoers entries yourself:

```sh
sudo tee /etc/sudoers.d/g15-panel <<EOF
$USER ALL=(root) NOPASSWD: /usr/bin/g15 power *
$USER ALL=(root) NOPASSWD: /usr/bin/g15 fan boost *
EOF
sudo chmod 440 /etc/sudoers.d/g15-panel
```

Either way, if the privileged call fails the control simply snaps back to the
real value on the next poll.

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

## Packaging: why this is not its own repo yet

Deliberate, for now. The widget and the CLI ship one contract (`g15 status`,
`g15 led effect`, …), and while both are changing every commit, keeping them in
one repo means one commit, one PR, and one place where a contract break shows
up. The cost is the copy-install above and no marketplace listing.

Everything else is already publish-shaped: reverse-DNS id, no `clonedFrom` in
the manifest, its own README and LICENSE, no files referenced outside this
directory. When the contract settles, splitting it out is:

```sh
git subtree split --prefix omarchy-plugin -b g15-omarchy-plugin
# push that branch as the root of a new repo, then
omarchy plugin add https://github.com/andeen171/omarchy-g15.git --enable
```

Nothing inside the plugin changes; only the repo's README install steps and the
version handshake (the plugin would then declare a minimum `g15` CLI version
rather than moving in lockstep with it). Submission after that is the
[marketplace issue template](https://github.com/HANCORE-linux/omarchy-plugin-marketplace),
which wants the external dependency (the `g15` CLI), the privilege boundary
(sudo for power modes), and a `preview.png`.

## History

`Widget.qml` (plugin `andeen171.g15`, g15-cli 0.2.0) was the first version: a
`BarWidget` that polled `g15 waybar` for a text label and ran the TUI on click,
a straight port of the Waybar custom module Omarchy 3 used before the shell
replaced Waybar. It is gone from the working tree — `git show <ref>:omarchy-plugin/Widget.qml`
— because `Panel.qml` is a superset: same readout, same click-to-TUI (now on
right click), plus the controls. The old widget stays in the repo history as
the minimal example of a `bar-widget` plugin, and the plain `shell.json`
command-module fallback for it is still documented in the
[main README](../README.md).

## License

MIT — see LICENSE.
