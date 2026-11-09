<p align="center"><img src="Resources/banner.svg" alt="Droppy" width="100%"></p>

# Droppy

Droppy is a drop-down terminal for macOS. It uses libghostty, the terminal core of Ghostty. A global hotkey moves the panel in from a screen edge. The same hotkey moves it out again.

## Features

- Global hotkey. The default is `ctrl+grave`.
- The panel shows on all Spaces and above full-screen apps.
- Tabs. The tab bar is at the bottom or at the top.
- Splits. Droppy can equalize them automatically.
- You set the position, alignment and size of the panel.
- You change the height with the mouse (drag the inner edge) or with cmd+j and cmd+k.
- Scrollback search in each pane.
- Bell (`bell-features`), desktop notifications (OSC 9 and OSC 777), notifications when a command stops (`notify-on-command-finish`) and tab progress (OSC 9;4).
- Overlay scrollbar (`scrollbar`). A preview shows the link below the mouse pointer.
- Plain-text config. Droppy applies changes immediately.
- All Ghostty options and themes.

## Requirements

- macOS 14 or later. Tested on macOS 15.
- Apple Silicon only. The build makes the library for the native architecture only.
- To build:
  - Xcode with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).
  - [mise](https://mise.jdx.dev). It installs Zig 0.17.0, as `mise.toml` specifies.
  - [just](https://just.systems).

## Build and install

Git does not track `Vendor/`. The second step creates it.

```sh
mise trust && mise install      # install Zig
scripts/build-ghostty.sh        # do one time: clone Ghostty v1.4.0, build libghostty into Vendor/
just build                      # make the release app at .build/Droppy.app
just install                    # replace /Applications/Droppy.app
```

To install to a different path, use `just install-dir=<path>.app install` or set `DROPPY_INSTALL_DIR`.

If Droppy runs, `just install` tells it to quit. If Droppy does not quit, the install stops and changes nothing.

`scripts/build-ghostty.sh ReleaseSmall` builds the library for size, not for speed. In a rough test, the binary was approximately 20% smaller and the terminal was approximately 18% slower.

## Configuration

The config file is `$XDG_CONFIG_HOME/droppy/config` or `~/.config/droppy/config`.

- Each line is `key = value`.
- `#` starts a comment.
- If there is no file, Droppy uses the defaults.
- If there is no file, Open Config makes one from a template with comments.
- Droppy applies changes to the file while it runs.

Droppy keys:

| Key | Default | Values |
|---|---|---|
| `hotkey` | `ctrl+grave` | Modifiers (`ctrl`, `opt`, `cmd`, `shift`) and one key, joined with `+` |
| `position` | `top` | `top`, `bottom`, `left`, `right`, `center` |
| `alignment` | `center` | `start`, `center`, `end` |
| `width` | `100%` | 20% to 100% |
| `height` | `40%` | 15% to 100% |
| `tab-bar` | `bottom` | `bottom`, `top` |
| `hide-on-focus-loss` | `true` | `true`, `false` |
| `border-width` | `1` | Points, 0 to 20. 0 removes the border |
| `border-sides` | `all` | `all`, `none`, or a comma-separated list of `top`, `bottom`, `left`, `right` |
| `border-color` | `auto` | `auto`, `#rrggbb`, `#rrggbbaa` |
| `corner-radius` | `0` | Points, 0 to 40. 0 gives square corners |
| `corner-radius-corners` | `all` | `all`, `none`, or a comma-separated list of `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| `opacity` | `1` | 0.1 to 1. Applies to all of the panel: text, tabs and border. Ghostty's `background-opacity` applies to the background only |
| `shadow` | `true` | `true`, `false` |
| `animation-duration` | `0.2` | Seconds, 0 to 2 |
| `auto-equalize-splits` | `false` | `true`, `false` |
| `launch-at-login` | `false` | `true`, `false` |

Droppy sends all other keys to Ghostty without change. Ghostty options, `keybind` and `theme` operate as the Ghostty documentation shows.

Example:

```
position = bottom
alignment = end
width = 40%
theme = Kanagawabones
font-size = 14
```

### Status-bar menu

| Item | Function |
|---|---|
| Secure Keyboard Entry | Turns secure input on or off. Droppy releases it when the panel hides or when Droppy is not active. Keybind action: `toggle_secure_input` |
| Open Config | Opens the config file |
| Reload Config | Reads the config file again |
| Open Config Reference | Opens a read-only copy of the template. The template lists the Ghostty options that Droppy reads, and their defaults |

If a config line has an error, the menu shows "Config line N: ...".

## Shortcuts

Droppy uses the Ghostty default macOS bindings for the actions it supports. Droppy changes the bindings for tab move, split focus and Keep Panel Visible. To change a shortcut, use `keybind`.

| Shortcut | Action |
|---|---|
| ctrl+grave | Show or hide the panel. Global. Config key: `hotkey` |
| cmd+t | New tab |
| cmd+1 ... cmd+8 | Go to tab 1 to 8 |
| cmd+9 | Go to the last tab |
| cmd+shift+[ , cmd+shift+] | Previous tab, next tab |
| cmd+opt+left, cmd+opt+right | Move the tab left, right. `move_tab:N` moves it N positions and wraps around |
| cmd+opt+p | Keep Panel Visible: the panel stays when it loses focus. Push again to stop. The border shows the accent colour while it is on. Also in the right-click menu. Action: `toggle_window_float_on_top`. A config reload sets `hide-on-focus-loss` again |
| Double-click a tab | Rename the tab. An empty name gives the automatic title again. Action: `prompt_surface_title` |
| cmd+w | Close the focused split or tab |
| cmd+opt+w | Close the tab |
| cmd+d, cmd+shift+d | Split right, split down |
| cmd+[ , cmd+] | Previous split, next split |
| cmd+shift+arrows | Focus the split in that direction |
| cmd+ctrl+arrows | Resize the split |
| cmd+ctrl+= | Equalize the splits |
| cmd+shift+return | Zoom the split |
| cmd+return | Make the panel fill the screen, or restore its size |
| cmd+j, cmd+k | Make the panel taller, shorter |
| cmd+c, cmd+v | Copy, paste |
| cmd+=, cmd+-, cmd+0 | Font size larger, smaller, default |
| Double-tap cmd | Jump mode. See below |
| cmd+f | Search the scrollback of the focused pane |
| return, cmd+g | Next match. return operates only in the search field |
| shift+return, cmd+shift+g | Previous match. shift+return operates only in the search field |
| esc | Close the search and go back to the terminal |
| cmd+, | Open the config |
| cmd+shift+, | Reload the config |
| cmd+z | Open a closed tab or split again. This operates only during `undo-timeout`. It restores the layout and directories, but not the processes |
| cmd+q | Quit |

### Jump mode

1. Double-tap cmd.
2. Each tab shows a letter from the top row (q to p). Each split in the current tab shows a letter and its directory.
3. Push a tab letter to go to that tab. Push a split letter to focus that split. Push the same letter again to stop jump mode.
4. After you focus a split, arrows show the directions where a neighbor exists. Push an arrow key to swap this split with its neighbor. The letter stays with the moved split.
5. To stop jump mode, double-tap cmd again or push esc.

## Known limitations

- Droppy does not open links with custom URL schemes.
- The app has an ad-hoc signature. Gatekeeper shows a warning on other Macs.
- cmd+k and cmd+j resize the panel. They replace the Ghostty bindings for clear screen and scroll to selection.

## Icons

The icon files are in `Resources/`. You must regenerate them only when the artwork changes:

```sh
ICON_RENDERER=<script> scripts/generate-icons.sh
```

The script reads `Resources/icon/*.svg`. `ICON_RENDERER` is a script that converts SVG to PNG.

## Credits

Droppy uses [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto and contributors (MIT licence). Parts of the terminal view code come from the Ghostty macOS app. See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).

Droppy has the MIT licence. See [LICENSE](LICENSE).
