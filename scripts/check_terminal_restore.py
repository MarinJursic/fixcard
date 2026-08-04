#!/usr/bin/env python3
"""Verify that a terminated interactive paste restores its terminal."""

from __future__ import annotations

import os
import pty
import select
import signal
import subprocess
import sys
import termios
import time
from pathlib import Path


def read_until(fd: int, marker: bytes, timeout_seconds: float) -> bytes:
    deadline = time.monotonic() + timeout_seconds
    output = bytearray()
    while marker not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"timed out waiting for {marker!r}; output={bytes(output)!r}")
        readable, _, _ = select.select([fd], [], [], remaining)
        if readable:
            output.extend(os.read(fd, 4096))
    return bytes(output)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_terminal_restore.py FIXCARD_BINARY", file=sys.stderr)
        return 2
    if os.name != "posix":
        print("terminal restoration check requires a POSIX pseudo-terminal", file=sys.stderr)
        return 2

    binary = Path(sys.argv[1]).resolve()
    master_fd, slave_fd = pty.openpty()
    original_mode = termios.tcgetattr(slave_fd)
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            [binary, "fix", "--paste"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
        )
        read_until(master_fd, b"Input is hidden, used once, and not saved.", 5.0)
        raw_mode = termios.tcgetattr(slave_fd)
        if raw_mode == original_mode:
            print("interactive paste did not put the pseudo-terminal in raw mode", file=sys.stderr)
            return 1

        process.send_signal(signal.SIGTERM)
        return_code = process.wait(timeout=5.0)
        process = None
        if return_code != -signal.SIGTERM:
            print(f"expected SIGTERM exit, got {return_code}", file=sys.stderr)
            return 1
        if termios.tcgetattr(slave_fd) != original_mode:
            print("interactive paste left the pseudo-terminal in raw mode", file=sys.stderr)
            return 1
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master_fd)
        os.close(slave_fd)

    print("SIGTERM restored the interactive paste pseudo-terminal")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
