#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd -- "$script_dir/.." && pwd -P)"

fail() {
  printf 'WinTime cross-build failed: %s\n' "$*" >&2
  exit 1
}

if [[ "$#" -ne 2 ]]; then
  fail "usage: $0 <x64|arm64> <output-filename.exe>"
fi

target_architecture="$1"
output_filename="$2"

case "$target_architecture" in
  x64)
    expected_host_architecture='x86_64'
    ;;
  arm64)
    expected_host_architecture='aarch64'
    ;;
  *)
    fail "unsupported target architecture '$target_architecture'; expected x64 or arm64"
    ;;
esac

[[ "$output_filename" != */* ]] \
  || fail "output filename must not contain a directory: '$output_filename'"
[[ "$output_filename" == *.exe ]] \
  || fail "output filename must end in .exe: '$output_filename'"
[[ -r /etc/os-release ]] || fail 'cannot identify the Linux distribution'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == 'ubuntu' ]] \
  || fail "this script supports Ubuntu runners; detected '${ID:-unknown}'"
[[ "$(uname -m)" == "$expected_host_architecture" ]] \
  || fail "target '$target_architecture' requires host '$expected_host_architecture'; detected '$(uname -m)'"
command -v makensis >/dev/null 2>&1 \
  || fail 'makensis is required; install the Ubuntu nsis package'

installer_script="$repository_root/installer/TimeSync.nsi"
output_directory="$repository_root/dist"
[[ -f "$installer_script" ]] || fail "installer definition is missing: '$installer_script'"

mkdir -p "$output_directory"
staging_directory="$(mktemp -d "$output_directory/.build.XXXXXXXX")"
cleanup() {
  rm -rf -- "$staging_directory"
}
trap cleanup EXIT

staged_installer="$staging_directory/$output_filename"
final_installer="$output_directory/$output_filename"

cd -- "$repository_root"
makensis \
  -V4 \
  "-DTARGET_ARCHITECTURE=$target_architecture" \
  "-DOUTPUT_FILE=$staged_installer" \
  "$installer_script"

[[ -s "$staged_installer" ]] \
  || fail "makensis reported success but did not create '$staged_installer'"
mv -f -- "$staged_installer" "$final_installer"
printf '%s\n' "$final_installer"
