#!/usr/bin/env python3
import json
import os
import sqlite3
import subprocess
import time
from datetime import date

TICK = 5
STATE_DIR = os.path.expanduser("~/.local/state/focustime")
DB_PATH = os.path.join(STATE_DIR, "focustime.db")


def init_db():
    os.makedirs(STATE_DIR, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute(
        "CREATE TABLE IF NOT EXISTS usage "
        "(day TEXT, app TEXT, seconds INTEGER, PRIMARY KEY (day, app))"
    )
    con.commit()
    return con


def locked():
    return subprocess.run(
        ["pgrep", "-x", "hyprlock"], stdout=subprocess.DEVNULL
    ).returncode == 0


def active_class():
    try:
        out = subprocess.run(
            ["hyprctl", "activewindow", "-j"],
            capture_output=True, text=True, timeout=2,
        ).stdout
        return (json.loads(out).get("class") or "").strip()
    except Exception:
        return ""


def main():
    con = init_db()
    while True:
        time.sleep(TICK)
        if locked():
            continue
        cls = active_class()
        if not cls:
            continue
        con.execute(
            "INSERT INTO usage (day, app, seconds) VALUES (?, ?, ?) "
            "ON CONFLICT(day, app) DO UPDATE SET seconds = seconds + ?",
            (date.today().isoformat(), cls, TICK, TICK),
        )
        con.commit()


if __name__ == "__main__":
    main()
