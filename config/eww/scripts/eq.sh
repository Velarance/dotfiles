#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

STATE="$HOME/.cache/eww-eq-gains"
STAMP="$HOME/.cache/eww-eq-stamp"
OUTDIR="$HOME/.config/easyeffects/output"

mkdir -p "$OUTDIR"
[ -e "$OUTDIR/Flat.json" ] || cp -f "$HOME/dotfiles/config/easyeffects/output/"*.json "$OUTDIR/" 2>/dev/null

declare -A PRESETS=(
    [Flat]="0 0 0 0 0 0 0 0 0 0"
    [Bass]="6 5 4 2 0 0 0 0 0 0"
    [Treble]="0 0 0 0 0 1 2 4 5 6"
    [Vocal]="-2 -1 0 2 4 4 3 1 0 -1"
    [Pop]="-1 0 2 3 3 1 0 -1 -1 -1"
    [Rock]="5 4 2 0 -1 -1 1 3 4 5"
    [Jazz]="3 2 1 2 -1 -1 0 1 2 3"
    [Classic]="4 3 2 1 -1 -1 0 2 3 4"
)

read_gains() { [ -f "$STATE" ] && cat "$STATE" || echo "0 0 0 0 0 0 0 0 0 0"; }

write_custom() {
    python3 - "$OUTDIR" "$@" <<'PY'
import json, sys, os
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
gains = [round(float(x)) for x in sys.argv[2:12]]
FREQS = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
def band(f, g):
    return {"frequency": float(f), "gain": float(g), "mode": "RLC (BT)", "mute": False,
            "q": 4.3, "slope": "x1", "solo": False, "type": "Bell", "width": 4.0}
ch = {f"band{i}": band(FREQS[i], gains[i]) for i in range(10)}
eq = {"balance": 0.0, "bypass": False, "input-gain": 0.0, "output-gain": 0.0,
      "mode": "IIR", "num-bands": 10, "pitch-left": 0.0, "pitch-right": 0.0,
      "split-channels": False, "left": ch, "right": json.loads(json.dumps(ch))}
json.dump({"output": {"blocklist": [], "equalizer#0": eq, "plugins_order": ["equalizer#0"]}},
          open(out + "/Custom.json", "w"), indent=2)
PY
}

case "$1" in
    preset)
        g="${PRESETS[$2]}"
        [ -n "$g" ] && echo "$g" > "$STATE"
        easyeffects -l "$2" >/dev/null 2>&1
        ;;
    set)
        read -ra G < <(read_gains)
        G[$2]=$(printf '%.0f' "$3")
        echo "${G[*]}" > "$STATE"
        st=$(date +%s%N); echo "$st" > "$STAMP"
        (
            sleep 0.30
            [ "$(cat "$STAMP" 2>/dev/null)" = "$st" ] || exit 0
            read -ra GG < <(read_gains)
            write_custom "${GG[@]}"
            easyeffects -l Custom >/dev/null 2>&1
        ) &
        ;;
    bypass)
        easyeffects --bypass-toggle >/dev/null 2>&1
        ;;
    get)
        read -ra G < <(read_gains)
        last=$(easyeffects -a output 2>/dev/null)
        byp=$(easyeffects -b 3 2>/dev/null)
        python3 -c "
import json
g=[float(x) for x in '''${G[*]}'''.split()]
print(json.dumps({'preset':'''${last}'''.strip(),'bypass':'${byp}'.strip()=='1','gains':g}))
"
        ;;
esac
