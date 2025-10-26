#!/bin/bash
set -euo pipefail

TELNET_PORT="${TELNET_PORT:-23}"
TELNET_LOGIN="${TELNET_LOGIN:-/bin/login}"
TELNETD_BIN="${TELNETD_BIN:-/bin/busybox}"
ENABLE_TELNET="${ENABLE_TELNET:-1}"
ENABLE_HTTP_CONSOLE="${ENABLE_HTTP_CONSOLE:-1}"
DOS_HTTP_PORT="${DOS_HTTP_PORT:-8080}"
DOS_HTTPD_BIN="${DOS_HTTPD_BIN:-/usr/local/bin/dos-httpd}"

ensure_dosuser_home() {
  local dos_entry dos_home dos_uid dos_gid owner_uid owner_gid
  local dos_user="dosuser"

  if ! dos_entry="$(getent passwd "${dos_user}")"; then
    echo "start-dos-services: unable to locate ${dos_user} account" >&2
    exit 1
  fi

  dos_home="$(printf '%s\n' "${dos_entry}" | cut -d: -f6)"
  dos_uid="$(printf '%s\n' "${dos_entry}" | cut -d: -f3)"
  dos_gid="$(printf '%s\n' "${dos_entry}" | cut -d: -f4)"

  if [ -z "${dos_home}" ]; then
    echo "start-dos-services: ${dos_user} home directory not defined" >&2
    exit 1
  fi

  if [ ! -d "${dos_home}" ]; then
    if ! install -d -m 755 -o "${dos_user}" -g "${dos_user}" "${dos_home}"; then
      echo "start-dos-services: failed to create ${dos_home}" >&2
      exit 1
    fi
  fi

  if runuser -u "${dos_user}" -- test -w "${dos_home}" 2>/dev/null; then
    return
  fi

  if ! owner_uid="$(stat -c '%u' "${dos_home}")"; then
    echo "start-dos-services: warning: unable to stat ${dos_home}" >&2
    return
  fi
  if ! owner_gid="$(stat -c '%g' "${dos_home}")"; then
    echo "start-dos-services: warning: unable to read group for ${dos_home}" >&2
    return
  fi

  if [ "${owner_uid}" -ne "${dos_uid}" ] || [ "${owner_gid}" -ne "${dos_gid}" ]; then
    echo "start-dos-services: adjusting ownership on ${dos_home} to ${dos_uid}:${dos_gid}" >&2
    if ! chown -R "${dos_user}:${dos_user}" "${dos_home}" 2>/dev/null; then
      echo "start-dos-services: warning: failed to adjust ownership on ${dos_home} (continuing; check volume permissions)" >&2
    fi
  fi

  if runuser -u "${dos_user}" -- test -w "${dos_home}" 2>/dev/null; then
    return
  fi

  if ! chmod u+rwx "${dos_home}" 2>/dev/null; then
    echo "start-dos-services: warning: unable to update permissions on ${dos_home}" >&2
  fi

  if runuser -u "${dos_user}" -- test -w "${dos_home}" 2>/dev/null; then
    return
  fi

  if command -v setfacl >/dev/null 2>&1; then
    if setfacl -m "u:${dos_user}:rwx" "${dos_home}" 2>/dev/null; then
      if runuser -u "${dos_user}" -- test -w "${dos_home}" 2>/dev/null; then
        return
      fi
    else
      echo "start-dos-services: warning: failed to grant ACL permissions on ${dos_home}" >&2
    fi
  fi

  echo "start-dos-services: warning: ${dos_home} remains unwritable by ${dos_user}; ensure the bind mount allows UID ${dos_uid} to write." >&2
}

ensure_dosuser_home

start_http_console() {
  if [ "${ENABLE_HTTP_CONSOLE}" != "1" ]; then
    return
  fi

  if [ ! -x "${DOS_HTTPD_BIN}" ]; then
    echo "start-dos-services: HTTP console disabled; missing ${DOS_HTTPD_BIN}" >&2
    return
  fi

  local args=()
  if [ -n "${DOS_HTTP_HOST:-}" ]; then
    args+=(--host "${DOS_HTTP_HOST}")
  fi
  if [ -n "${DOS_HTTP_PORT:-}" ]; then
    args+=(--port "${DOS_HTTP_PORT}")
  fi
  if [ -n "${DOS_HTTP_USER:-}" ]; then
    args+=(--user "${DOS_HTTP_USER}")
  fi
  if [ -n "${DOS_HTTP_SHELL:-}" ]; then
    args+=(--shell "${DOS_HTTP_SHELL}")
  fi
  if [ -n "${DOS_HTTP_ROWS:-}" ]; then
    args+=(--rows "${DOS_HTTP_ROWS}")
  fi
  if [ -n "${DOS_HTTP_COLS:-}" ]; then
    args+=(--cols "${DOS_HTTP_COLS}")
  fi
  if [ -n "${DOS_HTTP_LOG_LEVEL:-}" ]; then
    args+=(--log-level "${DOS_HTTP_LOG_LEVEL}")
  fi
  if [ -n "${DOS_HTTP_FONT_PATH:-}" ]; then
    args+=(--font-path "${DOS_HTTP_FONT_PATH}")
  fi

  set +e
  "${DOS_HTTPD_BIN}" "${args[@]}" &
  local status=$?
  local pid=$!
  set -e

  if [ "${status}" -ne 0 ]; then
    echo "start-dos-services: warning: HTTP console failed to launch (exit ${status})" >&2
    return
  fi

  echo "start-dos-services: HTTP console listening on ${DOS_HTTP_HOST:-0.0.0.0}:${DOS_HTTP_PORT} (pid ${pid})"
}

start_http_console

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
