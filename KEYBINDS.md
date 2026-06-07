# Keybinds

Mod key (`$mainMod`) = **SUPER** (Win key).
Apps resolved from `config/hypr/conf/defaults.conf`: terminal `kitty`, browser `zen-browser`, file manager `nautilus`, editor `mousepad`.

## Apps & launcher
| Keys | Action |
|------|--------|
| `CTRL + ALT + T` | Terminal (kitty) |
| `SUPER + B` | Browser (zen-browser) |
| `SUPER + E` | File manager (nautilus) |
| `ALT + SPACE` | App launcher (rofi drun) |
| `SUPER + V` | Clipboard history (cliphist) |

## Windows
| Keys | Action |
|------|--------|
| `SUPER + C` | Close window |
| `SUPER + F` | Fullscreen |
| `SUPER + T` | Toggle floating |
| `SUPER + J` | Toggle split direction (dwindle) |
| `SUPER + ←/→/↑/↓` | Move focus |
| `SUPER + drag LMB` | Move window with mouse |
| `SUPER + drag RMB` | Resize window with mouse |
| `SUPER + SHIFT + ←/→/↑/↓` | Resize active window (±100px) |
| `SUPER + CTRL + ←/→/↑/↓` | Move window in layout |

## Workspaces
| Keys | Action |
|------|--------|
| `SUPER + 1…0` | Switch to workspace 1–10 |
| `SUPER + SHIFT + 1…0` | Move window to workspace 1–10 |
| `SUPER + scroll` | Cycle workspaces |
| `SUPER + PageDown` | Jump to first empty workspace |

## Monitors
| Keys | Action |
|------|--------|
| `SUPER + ALT + ←/→` | Focus monitor left/right |
| `SUPER + ALT + SHIFT + ←/→` | Move window to prev/next monitor |

## Dropdown terminal (special workspace)
| Keys | Action |
|------|--------|
| `` SUPER + ` `` | Toggle dropdown terminal |
| `` SUPER + SHIFT + ` `` | Move window to dropdown workspace |

## Screenshots & wallpaper
| Keys | Action |
|------|--------|
| `PrintScreen` | Screenshot (full) → editor (swappy) |
| `SUPER + PrintScreen` | Screenshot of selected area |
| `SUPER + SHIFT + W` | Regenerate color scheme from current wallpaper |
| `SUPER + CTRL + W` | Pick a new wallpaper |
| `SUPER + SHIFT + B` | Relaunch waybar |

## Claude Code
| Keys | Action |
|------|--------|
| `ALT + C` | Screenshot → paste & submit into Claude (needs `wtype`, `lsof`) |
| `SUPER + SHIFT + P` | Open kitty running `claude` (socket `/tmp/kitty-claude`) |

## Media / Fn keys
| Keys | Action |
|------|--------|
| Brightness Up/Down | `brightnessctl` ±10% |
| Volume Up/Down | `pactl` ±5% |
| Mute | `wpctl` toggle |
| Mic Mute | `pactl` source mute toggle |
| Play / Pause / Next / Prev | `playerctl` |
| Calculator key | `qalculate-gtk` |
| Lock key | `hyprlock` |
| XF86Tools | settings menu (`settings.sh`) |

## System
| Keys | Action |
|------|--------|
| `SUPER + CTRL + Q` | Logout menu (wlogout) |

## VM passthrough
| Keys | Action |
|------|--------|
| `SUPER + P` | Enter `passthru` submap (sends SUPER to the VM) |
| `SUPER + Escape` | Exit passthru submap |

---

### Notes
- Source of truth: `config/hypr/conf/keybinding.conf` and `defaults.conf`.
- Targets **Hyprland 0.55+**: `SUPER + J` uses `layoutmsg, togglesplit` (the bare `togglesplit` dispatcher was removed); the stale `dwindle:pseudotile` and `misc:vfr` options are gone.
- Recovery: if the on-screen "config error" overlay appears, run `hyprctl configerrors` from a terminal (or TTY `Ctrl+Alt+F2`) to see the offending file:line.
