#!/usr/bin/env python3
"""Validate LaunchDeck search benchmark JSON against tracked upper bounds."""

import json
import pathlib
import sys


def fail(message: str) -> None:
    print(f"benchmark gate: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 3:
    fail("usage: validate-search-benchmark.py RESULT.json THRESHOLDS.json")

result_path = pathlib.Path(sys.argv[1])
threshold_path = pathlib.Path(sys.argv[2])
result = json.loads(result_path.read_text())
thresholds = json.loads(threshold_path.read_text())

if result.get("apps") != thresholds.get("apps"):
    fail(f"expected {thresholds.get('apps')} apps, got {result.get('apps')}")

failures = []
for metric, maximum in thresholds["maximums"].items():
    value = result.get(metric)
    if not isinstance(value, (int, float)):
        failures.append(f"{metric} is missing or not numeric")
    elif value > maximum:
        failures.append(f"{metric}={value:.3f} exceeds {maximum:.3f}")
    else:
        print(f"PASS {metric}: {value:.3f} <= {maximum:.3f}")

if failures:
    fail("; ".join(failures))
