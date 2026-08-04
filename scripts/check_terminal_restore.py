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
import tempfile
import time
from pathlib import Path


STARTUP_DELAYS_SECONDS = (0.0, 0.0001, 0.0005, 0.001, 0.002)


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


def check_startup_termination(command: list[Path], delay_seconds: float) -> None:
    master_fd, slave_fd = pty.openpty()
    original_mode = termios.tcgetattr(slave_fd)
    process = subprocess.Popen(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
    )
    try:
        if delay_seconds:
            time.sleep(delay_seconds)
        process.send_signal(signal.SIGTERM)
        return_code = process.wait(timeout=5.0)
        if return_code != -signal.SIGTERM:
            raise RuntimeError(f"expected SIGTERM exit, got {return_code}")
        if termios.tcgetattr(slave_fd) != original_mode:
            raise RuntimeError(
                f"startup SIGTERM after {delay_seconds}s left the terminal in raw mode"
            )
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master_fd)
        os.close(slave_fd)


def check_hidden_prompt_rejected(command: list[Path]) -> None:
    master_fd, slave_fd = pty.openpty()
    original_mode = termios.tcgetattr(slave_fd)
    try:
        with tempfile.TemporaryFile() as error_file:
            result = subprocess.run(
                command,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=error_file,
                timeout=5.0,
                check=False,
            )
            error_file.seek(0)
            error = error_file.read()
        if result.returncode == 0 or b"run without redirecting standard error" not in error:
            raise RuntimeError(f"hidden prompt was not rejected clearly: {error!r}")
        if termios.tcgetattr(slave_fd) != original_mode:
            raise RuntimeError("hidden prompt rejection changed the input terminal mode")
    finally:
        os.close(master_fd)
        os.close(slave_fd)


def check_split_terminals_rejected(command: list[Path]) -> None:
    input_master, input_slave = pty.openpty()
    prompt_master, prompt_slave = pty.openpty()
    input_mode = termios.tcgetattr(input_slave)
    prompt_mode = termios.tcgetattr(prompt_slave)
    try:
        result = subprocess.run(
            command,
            stdin=input_slave,
            stdout=prompt_slave,
            stderr=prompt_slave,
            timeout=5.0,
            check=False,
        )
        output = read_until(prompt_master, b"same terminal as standard input", 5.0)
        if result.returncode == 0:
            raise RuntimeError(f"split prompt terminals were accepted: {output!r}")
        if termios.tcgetattr(input_slave) != input_mode:
            raise RuntimeError("split prompt rejection changed the input terminal mode")
        if termios.tcgetattr(prompt_slave) != prompt_mode:
            raise RuntimeError("split prompt rejection changed the prompt terminal mode")
    finally:
        os.close(input_master)
        os.close(input_slave)
        os.close(prompt_master)
        os.close(prompt_slave)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_terminal_restore.py FIXCARD_BINARY", file=sys.stderr)
        return 2
    if os.name != "posix":
        print("terminal restoration check requires a POSIX pseudo-terminal", file=sys.stderr)
        return 2

    binary = Path(sys.argv[1]).resolve()
    short_binary = binary.with_name("fix")
    command = [short_binary]
    check_hidden_prompt_rejected(command)
    check_split_terminals_rejected(command)
    for delay_seconds in STARTUP_DELAYS_SECONDS:
        for _ in range(4):
            check_startup_termination(command, delay_seconds)

    master_fd, slave_fd = pty.openpty()
    original_mode = termios.tcgetattr(slave_fd)
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            command,
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

    print(
        "installed fix rejected hidden prompts and restored its terminal during startup and input"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
