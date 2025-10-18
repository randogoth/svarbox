#!/bin/bash
set -euo pipefail

SVARDOS_BASE_DIR="/opt/svardos/base"
SVARDOS_CACHE="/opt/svardos/cache"
SVARDOS_IMG="${SVARDOS_CACHE}/svardos.img"
DEFAULT_REL="download/20250427/svardos-20250427-floppy-1.44M.zip"
DEFAULT_BASE="http://svardos.org"

if [ -z "${SVARDOS_IMG_URL:-}" ]; then
  homepage="$(
    curl -fsSL "${DEFAULT_BASE}/" 2>/dev/null || true
  )"
  discovered_rel=""
  if [ -n "$homepage" ]; then
    for pattern in 'download/[0-9]+/svardos-[0-9]+-floppy-1\.44M\.zip' 'download/[0-9]+/svardos-[0-9]+-usb\.zip'; do
      candidate="$(printf '%s' "$homepage" | grep -Eo "$pattern" | head -n1)"
      if [ -n "$candidate" ]; then
        discovered_rel="$candidate"
        break
      fi
    done
  fi
  if [ -n "$discovered_rel" ]; then
    SVARDOS_IMG_URL="${DEFAULT_BASE}/${discovered_rel}"
  else
    SVARDOS_IMG_URL="${DEFAULT_BASE}/${DEFAULT_REL}"
  fi
fi

if [ -e "${SVARDOS_BASE_DIR}/COMMAND.COM" ] || [ -e "${SVARDOS_BASE_DIR}/command.com" ]; then
  exit 0
fi

mkdir -p "${SVARDOS_BASE_DIR}" "${SVARDOS_CACHE}"

tmp_archive="${SVARDOS_CACHE}/svardos_download"
rm -f "${tmp_archive}" "${SVARDOS_IMG}"

echo "Fetching SvarDOS base from ${SVARDOS_IMG_URL}"
curl -fsSL "${SVARDOS_IMG_URL}" -o "${tmp_archive}"

mime_type="$(file -b --mime-type "${tmp_archive}")"
case "${mime_type}" in
  application/zip)
    unzip -o "${tmp_archive}" -d "${SVARDOS_CACHE}" >/dev/null
    ;;
  application/x-bzip2|application/x-gzip|application/x-xz)
    tar -xf "${tmp_archive}" -C "${SVARDOS_CACHE}"
    ;;
  application/octet-stream)
    # assume this is already a raw image
    cp "${tmp_archive}" "${SVARDOS_IMG}"
    ;;
  *)
    echo "Unsupported SvarDOS payload type: ${mime_type}" >&2
    exit 1
    ;;
esac

if [ ! -f "${SVARDOS_IMG}" ]; then
  # try to locate the image file
  candidate="$(find "${SVARDOS_CACHE}" -maxdepth 1 -type f \( -iname '*svardos*.img' -o -iname '*.ima' -o -iname '*.img' \) | head -n1)"
  if [ -z "${candidate}" ]; then
    echo "Could not locate a SvarDOS disk image after extraction." >&2
    exit 1
  fi
  mv "${candidate}" "${SVARDOS_IMG}"
fi

rm -rf "${SVARDOS_BASE_DIR}"/*
mkdir -p "${SVARDOS_BASE_DIR}"

# Copy contents of FAT image into the base directory
mcopy -s -i "${SVARDOS_IMG}" ::* "${SVARDOS_BASE_DIR}/"

rm -f "${SVARDOS_IMG}" "${tmp_archive}"
rm -rf "${SVARDOS_CACHE}"
echo "SvarDOS base copied to ${SVARDOS_BASE_DIR}"
