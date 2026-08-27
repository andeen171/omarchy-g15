# G15 — Omarchy bar plugin

Dell G15 (5520) CPU/GPU temperatures and fan rpm in the [Omarchy](https://omarchy.org)
bar, with a panel for the two things you would otherwise open a terminal for:
the power mode and the RGB keyboard backlight.

- **Bar:** `󰍛 54°  󰢮 53°`, tooltip with both fan speeds and the current power mode.
- **Panel (left click):** temperature meters, power mode chips
  (quiet / balanced / performance / G-Mode), keyboard brightness slider and
  effect chips (static / pulse / morph / cycle / rainbow).
- **Right click:** opens the full `g15` TUI, where per-zone colors live.

## Requires

The [`g15` CLI](https://github.com/andeen171/g15-cli) on `PATH` (`yay -S g15`).
The widget only ever runs:

| Action | Command |
|---|---|
| poll | `g15 status` |
| power mode | `sudo -n g15 power <mode>` (configurable) |
| brightness | `g15 led brightness <0-100>` |
| effect | `g15 led effect <name>` |

Polling reads hwmon and `~/.config/g15/state` only — never the USB LED device,
which must not be opened concurrently.

## Install

```sh
omarchy plugin add https://github.com/andeen171/g15-cli.git --enable
```

or, from a clone of the g15-cli repo (the shell refuses symlinked plugin dirs,
so this is a copy):

```sh
cp -r omarchy-plugin ~/.config/omarchy/plugins/io.github.andeen171.g15
omarchy plugin validate ~/.config/omarchy/plugins/io.github.andeen171.g15
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.andeen171.g15 left
```

## Privileges

Reading needs nothing. LED writes go over USB and need only the udev rule the
CLI ships. **Switching the power mode needs root** (`acpi_call` WMI), so the
panel's chips shell out through `sudo`. Grant it passwordless:

```sh
echo "$USER ALL=(root) NOPASSWD: /usr/bin/g15 power *" | sudo tee /etc/sudoers.d/g15-power
```

Without that line the chips are inert (sudo -n fails silently) and the mode
shown is whatever the CLI last recorded. Point `powerCommand` at `doas` or a
wrapper of your own in the widget settings if you prefer.

## License

MIT — see LICENSE.
