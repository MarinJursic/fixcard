#!/usr/bin/env python3
"""Gate release-binary process startup without third-party Python packages."""

from __future__ import annotations

import math
import statistics
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_startup.py BINARY MAX_P95_MILLISECONDS", file=sys.stderr)
        return 2

    binary = Path(sys.argv[1]).resolve()
    threshold_ms = float(sys.argv[2])
    samples: list[float] = []
    for _ in range(30):
        started = time.perf_counter_ns()
        result = subprocess.run(
            [binary, "--version"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        if result.returncode != 0:
            print(f"{binary} --version exited {result.returncode}", file=sys.stderr)
            return 1
        samples.append(elapsed_ms)

    ordered = sorted(samples)
    p95_index = math.ceil(len(ordered) * 0.95) - 1
    p95_ms = ordered[p95_index]
    print(
        f"startup median={statistics.median(ordered):.2f}ms "
        f"p95={p95_ms:.2f}ms target=<{threshold_ms:.2f}ms"
    )
    if p95_ms >= threshold_ms:
        print("startup p95 exceeded the target", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
