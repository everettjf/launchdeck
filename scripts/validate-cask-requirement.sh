#!/bin/bash
# Fails when the Homebrew cask's `depends_on macos:` does not match the app's deployment
# target in project.yml. A cask that allows an older macOS installs an app that won't open.
#
# usage: scripts/validate-cask-requirement.sh <project.yml> <launchdeck.rb>

set -euo pipefail

project_file="${1:-}"
cask_file="${2:-}"
[[ -f "$project_file" && -f "$cask_file" ]] || {
  echo "usage: $0 <project.yml> <cask.rb>" >&2
  exit 64
}

deployment_target="$(ruby -e '
  match = File.read(ARGV.fetch(0)).match(/^\s*macOS:\s*"?([0-9]+(?:\.[0-9]+)*)"?/)
  abort "macOS deployment target not found in project.yml" unless match
  puts match[1]
' "$project_file")"

cask_symbol="$(ruby -e '
  match = File.read(ARGV.fetch(0)).match(/^\s*depends_on\s+macos:\s*(?:">=\s*)?:?([a-z_]+)/)
  abort "depends_on macos: <symbol> not found in the cask" unless match
  puts match[1]
' "$cask_file")"

cask_version="$(brew ruby -e '
  version = MacOSVersion::SYMBOLS[ARGV.fetch(0).to_sym]
  abort "Homebrew does not know macOS :#{ARGV.fetch(0)}" unless version
  puts version
' "$cask_symbol")"

# macOS 11 and later are identified by their major version alone.
deployment_major="${deployment_target%%.*}"
cask_major="${cask_version%%.*}"
if [[ "$deployment_major" != "$cask_major" ]]; then
  echo "cask requirement mismatch: project.yml targets macOS $deployment_target but the cask declares :$cask_symbol (macOS $cask_version)." >&2
  echo "Update 'depends_on macos:' in the cask to match the deployment target." >&2
  exit 1
fi

echo "cask requirement: :$cask_symbol (macOS $cask_version) matches deployment target $deployment_target"
