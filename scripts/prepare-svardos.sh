#!/bin/bash
set -euo pipefail

SVARDOS_ROOT="${SVARDOS_ROOT:-/opt/svardos}"
SVARDOS_BASE_DIR="${SVARDOS_BASE_DIR:-${SVARDOS_ROOT}/base}"
DEFAULT_URL="http://svardos.org/download/20250427/svardos-20250427-dosemu.zip"
ARCHIVE_URL="${SVARDOS_IMG_URL:-$DEFAULT_URL}"

# Skip work if the base tree already exists (unless SVARDOS_REFRESH is set)
if [ -z "${SVARDOS_REFRESH:-}" ] && [ -e "${SVARDOS_BASE_DIR}/COMMAND.COM" ]; then
  exit 0
fi

mkdir -p "${SVARDOS_BASE_DIR}"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

archive_path="${tmpdir}/svardos.zip"
unpack_dir="${tmpdir}/unpacked"

echo "Fetching SvarDOS base from ${ARCHIVE_URL}"
curl -fsSL "${ARCHIVE_URL}" -o "${archive_path}"

unzip -q "${archive_path}" -d "${unpack_dir}"

# Some archives might unpack into a single top-level directory; flatten it if so.
if [ "$(find "${unpack_dir}" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ] && \
   [ "$(find "${unpack_dir}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
  unpack_dir="$(find "${unpack_dir}" -mindepth 1 -maxdepth 1 -type d)"
fi

rm -rf "${SVARDOS_BASE_DIR:?}/"*
cp -a "${unpack_dir}/." "${SVARDOS_BASE_DIR}/"

echo "SvarDOS base copied to ${SVARDOS_BASE_DIR}"
