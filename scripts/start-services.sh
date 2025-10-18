#!/bin/bash
set -euo pipefail

TELNET_PORT="${TELNET_PORT:-23}"
TELNET_LOGIN="${TELNET_LOGIN:-/bin/login}"
TELNETD_BIN="${TELNETD_BIN:-/bin/busybox}"
ENABLE_TELNET="${ENABLE_TELNET:-1}"

if [ "$ENABLE_TELNET" = "1" ]; then
  if [ ! -x "$TELNETD_BIN" ]; then
    echo "Telnet disabled: telnetd binary not found at $TELNETD_BIN" >&2
  else
    echo "Starting telnetd on port $TELNET_PORT"
    if ! "$TELNETD_BIN" telnetd -p "$TELNET_PORT" -l "$TELNET_LOGIN"; then
      echo "Warning: failed to launch telnetd; SSH remains available." >&2
    fi
  fi
fi

exec /usr/sbin/sshd -D -e
