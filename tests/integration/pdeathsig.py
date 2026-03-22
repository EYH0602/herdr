#!/usr/bin/env python3
"""Exec a command with PR_SET_PDEATHSIG — receive a signal when parent dies.

Usage: pdeathsig.py SIGNAL COMMAND [ARGS...]

Fallback for systems without `setpriv --pdeathsig`.
"""
import ctypes
import ctypes.util
import os
import signal
import sys

PR_SET_PDEATHSIG = 1

SIGNALS = {
    "TERM": signal.SIGTERM, "SIGTERM": signal.SIGTERM,
    "INT": signal.SIGINT, "SIGINT": signal.SIGINT,
    "HUP": signal.SIGHUP, "SIGHUP": signal.SIGHUP,
    "KILL": signal.SIGKILL, "SIGKILL": signal.SIGKILL,
}

def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} SIGNAL COMMAND [ARGS...]", file=sys.stderr)
        return 2
    sig_name = sys.argv[1]
    argv = sys.argv[2:]
    if sig_name not in SIGNALS:
        print(f"unknown signal: {sig_name}", file=sys.stderr)
        return 2
    sig = SIGNALS[sig_name]
    libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
    if libc.prctl(PR_SET_PDEATHSIG, sig, 0, 0, 0) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
    # Race fix: parent may have died before prctl took effect
    if os.getppid() == 1:
        os.kill(os.getpid(), sig)
    os.execvp(argv[0], argv)
    return 127

if __name__ == "__main__":
    raise SystemExit(main())
