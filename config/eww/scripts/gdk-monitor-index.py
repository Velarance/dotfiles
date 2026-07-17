#!/usr/bin/env python3

import json
import math
import sys

try:
    import gi

    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
except (ImportError, ValueError):
    raise SystemExit(1)


ODD_TRANSFORMS = {1, 3, 5, 7}


def finite_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def monitor_geometry(target):
    required = ("x", "y", "width", "height")
    if not all(finite_number(target.get(key)) for key in required):
        return None

    scale = target.get("scale", 1)
    transform = target.get("transform", 0)
    if not finite_number(scale) or scale <= 0:
        return None
    if not isinstance(transform, int) or isinstance(transform, bool):
        return None

    width = target["width"]
    height = target["height"]
    if width <= 0 or height <= 0:
        return None
    if transform in ODD_TRANSFORMS:
        width, height = height, width

    return (
        float(target["x"]),
        float(target["y"]),
        float(width) / float(scale),
        float(height) / float(scale),
    )


def close_enough(left, right):
    return abs(float(left) - float(right)) <= 1.0


def main():
    try:
        target = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 1
    if not isinstance(target, dict):
        return 1

    display = Gdk.Display.get_default()
    expected_geometry = monitor_geometry(target)
    if display is None or expected_geometry is None:
        return 1

    monitors = []
    for index in range(display.get_n_monitors()):
        monitor = display.get_monitor(index)
        geometry = monitor.get_geometry()
        monitors.append(
            (
                index,
                monitor.get_model() or "",
                (geometry.x, geometry.y, geometry.width, geometry.height),
            )
        )

    geometry_matches = [
        item
        for item in monitors
        if all(
            close_enough(actual, expected)
            for actual, expected in zip(item[2], expected_geometry)
        )
    ]
    if len(geometry_matches) == 1:
        print(geometry_matches[0][0])
        return 0

    target_model = target.get("model")
    if isinstance(target_model, str) and target_model:
        model_matches = [item for item in monitors if item[1] == target_model]
        if len(model_matches) == 1:
            print(model_matches[0][0])
            return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
