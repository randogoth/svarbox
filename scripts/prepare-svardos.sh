#!/bin/bash
set -euo pipefail

SVARDOS_BUILD=20250427
SVARDOS_ROOT="${SVARDOS_ROOT:-/opt/svardos}"
SVARDOS_BASE_DIR="${SVARDOS_BASE_DIR:-${SVARDOS_ROOT}/base}"
SVARDOS_URL="http://svardos.org/download/${SVARDOS_BUILD}/svardos-${SVARDOS_BUILD}-dosemu.zip"
ARCHIVE_URL="${SVARDOS_IMG_URL:-$SVARDOS_URL}"

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

# Adjust installer to place pkg.cfg where modern pkg expects it.
install_bat="${unpack_dir}/INSTALL.BAT"
if [ -f "${install_bat}" ]; then
  sed -i 's|cfg\\pkg\.cfg|PKG.CFG|Ig' "${install_bat}"
fi

autoexec_bat="${unpack_dir}/AUTOEXEC.BAT"
if [ -f "${autoexec_bat}" ] && ! grep -qi '^SET[[:space:]]\+PKGCFG=' "${autoexec_bat}"; then
  tmp_autoexec="${tmpdir}/autoexec.new"
  awk '
    BEGIN{added=0}
    {
      print
      if (!added && toupper($0) ~ /^SET[[:space:]]+DOSDIR=/) {
        print "SET PKGCFG=%DOSDIR%\\PKG.CFG"
        added=1
      }
    }
  ' "${autoexec_bat}" > "${tmp_autoexec}"
  mv "${tmp_autoexec}" "${autoexec_bat}"
fi

rm -rf "${SVARDOS_BASE_DIR:?}/"*
cp -a "${unpack_dir}/." "${SVARDOS_BASE_DIR}/"

echo "SvarDOS base copied to ${SVARDOS_BASE_DIR}"
