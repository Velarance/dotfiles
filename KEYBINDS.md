# Keybinds

Mod key (`$mainMod`) = **SUPER** (Win key).
Apps from `config/hypr/conf/defaults.conf`: browser `zen-browser`, file manager `nautilus`, terminal `kitty`.
Lines marked **(personal)** are velarance's additions on top of the say8hi defaults.

## Apps & launcher
| Keys | Action |
|------|--------|
| `SUPER + RETURN` | Terminal (kitty) **(personal)** |
| `SUPER + M` | App launcher (rofi drun) **(personal)** |
| `SUPER + B` | Browser (zen-browser) |
| `SUPER + E` | File manager (nautilus) |
| `SUPER + C` | Clipboard history (cliphist) |
| `SUPER + SHIFT + R` | Wipe clipboard history **(personal)** |

## Windows
| Keys | Action |
|------|--------|
| `SUPER + Q` | Close window **(personal)** |
| `SUPER + T` | Toggle split direction (dwindle) |
| `SUPER + F` | Toggle floating **(personal)** |
| `SUPER + SHIFT + F` | Fullscreen **(personal)** |
| `SUPER + ←/→/↑/↓` | Move focus |
| `SUPER + drag LMB` | Move window with mouse |
| `SUPER + drag RMB` | Resize window with mouse |
| `SUPER + SHIFT + ←/→/↑/↓` | Resize active window (±100px) |
| `SUPER + CTRL + ←/→/↑/↓` | Move window in layout |

## Monitors
| Keys | Action |
|------|--------|
| `SUPER + ALT + ←/→` | Focus monitor left/right |
| `SUPER + ALT + SHIFT + ←/→` | Move window to prev/next monitor |

## Workspaces
| Keys | Action |
|------|--------|
| `SUPER + 1…0` | Switch to workspace 1–10 |
| `SUPER + SHIFT + 1…0` | Move window to workspace 1–10 |
| `SUPER + scroll` | Cycle workspaces |
| `SUPER + PageDown` | Jump to first empty workspace |

## Special workspaces
| Keys | Action |
|------|--------|
| `` SUPER + ` `` | Toggle dropdown terminal |
| `` SUPER + SHIFT + ` `` | Move window to dropdown |
| `SUPER + S` | Toggle special workspace "magic" **(personal)** |
| `SUPER + SHIFT + S` | Move window to special "magic" **(personal)** |

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

## System
| Keys | Action |
|------|--------|
| `SUPER + X` | Lock screen (loginctl lock-session) **(personal)** |
| `SUPER + CTRL + Q` | Logout menu (wlogout) |
| `SUPER + SHIFT + Escape` | Exit Hyprland **(personal)** |

## Volume / media (combos)
| Keys | Action |
|------|--------|
| `SUPER + PageUp / PageDown` | Volume up / down (wpctl) **(personal)** |
| `SUPER + Home` | Mute toggle **(personal)** |

## Hardware / Fn keys
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

## VM passthrough
| Keys | Action |
|------|--------|
| `SUPER + P` | Enter `passthru` submap (sends SUPER to the VM) |
| `SUPER + Escape` | Exit passthru submap |

---

### Notes
- Source of truth: `config/hypr/conf/keybinding.conf` and `defaults.conf`.
- Targets **Hyprland 0.55+**: `SUPER + J` uses `layoutmsg, togglesplit`; the stale `dwindle:pseudotile` and `misc:vfr` options are gone.
- say8hi defaults replaced by personal keys (and removed): terminal `CTRL+ALT+T` → `SUPER+RETURN`, launcher `ALT+SPACE` → `SUPER+M`, close `SUPER+C` → `SUPER+Q`, fullscreen `SUPER+F` → `SUPER+SHIFT+F`.
- Recovery: if the on-screen "config error" overlay appears, run `hyprctl configerrors` from a terminal (or TTY `Ctrl+Alt+F2`).
