#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOS_SHELL="${ROOT_DIR}/scripts/dos-shell"

if [ ! -x "${DOS_SHELL}" ]; then
  echo "dos-shell not found or not executable at ${DOS_SHELL}" >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

stub_bin="${tmp_root}/bin"
mkdir -p "${stub_bin}"

cat > "${stub_bin}/dosemu" <<'EOF'
#!/bin/sh
echo "dosemu stub invoked with: $*" >&2
exit 0
EOF
chmod +x "${stub_bin}/dosemu"

run_case() {
  local name="$1"
  local allow_mode="$2"
  local reserved="$3"
  local expected_files="$4"
  shift 4
  local asserts=("$@")

  local case_dir="${tmp_root}/${name}"
  local home_dir="${case_dir}/home"
  local base_dir="${case_dir}/svardos_base"
  local allowed_repo="${case_dir}/allowed_repo"
  local allow_list="${case_dir}/allowed_list"
  local extra_root="${case_dir}/extra_drives"

  mkdir -p "${home_dir}" "${base_dir}" "${allowed_repo}" "${extra_root}"

  # Populate minimal base image
  echo "base-${name}" > "${base_dir}/BASE.TXT"

  # Populate allowed repo fixtures
  echo "common-${name}" > "${allowed_repo}/common.txt"
  mkdir -p "${allowed_repo}/subdir"
  echo "sub-${name}" > "${allowed_repo}/subdir/sub.txt"
  echo "denied-${name}" > "${allowed_repo}/denied.txt"

  # Prepare allow list (filled later per mode)
  : > "${allow_list}"

  # Create extra drive scaffolding
  mkdir -p "${extra_root}/F"
  echo "driveF-${name}" > "${extra_root}/F/file.txt"
  mkdir -p "${extra_root}/D"
  echo "driveD-${name}" > "${extra_root}/D/file.txt"

  # Additional file for list mode
  if [ "${allow_mode}" = "list" ]; then
    {
      echo "common.txt"
      echo "subdir/sub.txt"
    } > "${allow_list}"
  fi

  # Expected files in C: after sync
  IFS=',' read -ra expected_array <<< "${expected_files}"

  (
    export PATH="${stub_bin}:${PATH}"
    export HOME="${home_dir}"
    export SVARDOS_ROOT="${case_dir}/svardos_root"
    export SVARDOS_BASE="${base_dir}"
    export DOS_FORCE_INSTALL=1
    export DOS_ALLOW_MODE="${allow_mode}"
    export DOS_EXTRA_DRIVE_ROOT="${extra_root}"
    export DOS_RESERVED_DRIVES="${reserved}"
    export DOS_ALLOWED_REPO="${allowed_repo}"
    export DOS_ALLOWED_LIST="${allow_list}"
    "${DOS_SHELL}" >/dev/null
  )

  local c_drive="${home_dir}/.dosemu/drive_c"

  for rel_path in "${expected_array[@]}"; do
    if [ ! -f "${c_drive}/${rel_path}" ]; then
      echo "[${name}] expected file missing in C: ${rel_path}" >&2
      exit 1
    fi
  done

  for assert in "${asserts[@]}"; do
    case "${assert}" in
      expect_symlink:*)
        local letter="${assert#expect_symlink:}"
        local link="${home_dir}/.dosemu/drive_${letter,,}"
        if [ ! -L "${link}" ]; then
          echo "[${name}] expected symlink for drive ${letter^^}: not found" >&2
          exit 1
        fi
        ;;
      expect_absent:*)
        local letter="${assert#expect_absent:}"
        local link="${home_dir}/.dosemu/drive_${letter,,}"
        if [ -e "${link}" ]; then
          echo "[${name}] expected drive ${letter^^}: to be absent, found $(ls -ld "${link}")" >&2
          exit 1
        fi
        ;;
      expect_no_file:*)
        local rel="${assert#expect_no_file:}"
        if [ -e "${c_drive}/${rel}" ]; then
          echo "[${name}] unexpected file present in C: ${rel}" >&2
          exit 1
        fi
        ;;
    esac
  done

  echo "[${name}] OK"
}

run_case "allow-all" "all" "CDE" "BASE.TXT,common.txt,subdir/sub.txt,denied.txt" \
  "expect_symlink:f" "expect_absent:d"

run_case "allow-list-reserved-override" "list" "C" "BASE.TXT,common.txt,subdir/sub.txt" \
  "expect_symlink:f" "expect_symlink:d" "expect_no_file:denied.txt"

echo "All tests passed."
