#!/usr/bin/env bash
set -Eeuo pipefail

node_version='24.21.0'
node_architecture="$(uname -m)"

case "$node_architecture" in
  x86_64)
    node_distribution_architecture='x64'
    node_archive_checksum='fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6'
    ;;
  aarch64)
    node_distribution_architecture='arm64'
    node_archive_checksum='6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2'
    ;;
  *)
    printf 'Node.js runtime is unavailable for runner architecture %s.\n' "$node_architecture" >&2
    exit 1
    ;;
esac

node_archive="node-v${node_version}-linux-${node_distribution_architecture}.tar.xz"
node_release_url="https://nodejs.org/dist/v${node_version}"
node_install_directory="${RUNNER_TEMP:?RUNNER_TEMP is required}/node-v${node_version}-${node_distribution_architecture}"
node_work_directory="$(mktemp -d "${RUNNER_TEMP}/node-runtime.XXXXXXXX")"
cleanup() {
  rm -rf -- "$node_work_directory"
}
trap cleanup EXIT

curl --fail --location --silent --show-error \
  --output "$node_work_directory/$node_archive" \
  "$node_release_url/$node_archive"

printf '%s  %s\n' "$node_archive_checksum" "$node_work_directory/$node_archive" \
  | sha256sum --check --status \
  || { echo "Node.js archive checksum verification failed for $node_archive." >&2; exit 1; }

mkdir -p "$node_install_directory"
tar --extract --xz --file "$node_work_directory/$node_archive" \
  --directory "$node_install_directory" \
  --strip-components=1
[[ -x "$node_install_directory/bin/node" ]] \
  || { echo 'Verified Node.js archive did not contain bin/node.' >&2; exit 1; }

path_file="${FORGEJO_PATH:-${GITHUB_PATH:-}}"
[[ -n "$path_file" ]] || {
  echo 'Forgejo did not provide a PATH command file.' >&2
  exit 1
}
printf '%s\n' "$node_install_directory/bin" >> "$path_file"
export PATH="$node_install_directory/bin:$PATH"

node --version | grep --fixed-strings --quiet "v${node_version}" \
  || { printf 'Installed Node.js runtime does not match v%s.\n' "$node_version" >&2; exit 1; }
printf 'Installed verified Node.js %s for %s.\n' "$node_version" "$node_architecture"
