#!/usr/bin/env python3
import json
import os
import sqlite3
from datetime import date

DB_PATH = os.path.expanduser("~/.local/state/focustime/focustime.db")


def fmt(seconds):
    minutes = seconds // 60
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def main():
    if not os.path.exists(DB_PATH):
        print(json.dumps({"text": "󰔛 0m", "tooltip": "No focus data yet"}))
        return

    con = sqlite3.connect(DB_PATH)
    today = date.today().isoformat()
    rows = con.execute(
        "SELECT app, seconds FROM usage WHERE day = ? ORDER BY seconds DESC",
        (today,),
    ).fetchall()

    total = sum(s for _, s in rows)
    lines = [f"{app.title():<18} {fmt(s)}" for app, s in rows[:6]]
    tooltip = f"Today — {fmt(total)}\n\n" + ("\n".join(lines) if lines else "—")
    print(json.dumps({"text": f"󰔛 {fmt(total)}", "tooltip": tooltip}))


if __name__ == "__main__":
    main()
