#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project_file="$project_root/project.yml"
release_branch="${LAUNCHDECK_RELEASE_BRANCH:-main}"
github_repo="${LAUNCHDECK_GITHUB_REPO:-everettjf/launchdeck}"
tap_repo="${LAUNCHDECK_HOMEBREW_TAP:-git@github.com:everettjf/homebrew-tap.git}"
tap_cask_path="Casks/launchdeck.rb"

fail() {
  echo "release-patch: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
usage: scripts/release-patch.sh

Increments LaunchDeck's patch version, tests, signs, notarizes, publishes a
GitHub Release, and updates everettjf/homebrew-tap.

Required environment variables:
  APPLE_ID
  APPLE_SPECIFIC_PASSWORD
  APPLE_TEAM_ID

Optional environment variables:
  LAUNCHDECK_RELEASE_BRANCH   Git branch to publish (default: main)
  LAUNCHDECK_GITHUB_REPO      GitHub owner/repository (default: everettjf/launchdeck)
  LAUNCHDECK_HOMEBREW_TAP     Tap clone URL (default: git@github.com:everettjf/homebrew-tap.git)
  LAUNCHDECK_RELEASE_DIR      Persistent artifact directory
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
[[ $# -eq 0 ]] || { usage >&2; exit 64; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_environment() {
  [[ -n "${!1:-}" ]] || fail "required environment variable is missing: $1"
}

normalize_version() {
  local value="${1#v}"
  if [[ "$value" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    printf '%s.%s.0\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$value"
  else
    fail "invalid semantic version: $1"
  fi
}

for command in brew codesign ditto gh git ruby security shasum swift xcodebuild xcodegen xcrun; do
  require_command "$command"
done
for variable in APPLE_ID APPLE_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
  require_environment "$variable"
done

[[ -f "$project_file" ]] || fail "project configuration not found: $project_file"
[[ -z "$(git -C "$project_root" status --porcelain)" ]] || fail "commit or stash all changes before releasing"
[[ "$(git -C "$project_root" branch --show-current)" == "$release_branch" ]] || \
  fail "releases must run from $release_branch"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is invalid; run: gh auth login -h github.com"

signing_identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
[[ -n "$signing_identity" ]] || fail "no Developer ID Application identity is available in the keychain"

git -C "$project_root" fetch origin "$release_branch" --tags
head_commit="$(git -C "$project_root" rev-parse HEAD)"
remote_commit="$(git -C "$project_root" rev-parse "origin/$release_branch")"
[[ "$head_commit" == "$remote_commit" ]] || fail "HEAD must match origin/$release_branch before a release"

latest_tag="$(git -C "$project_root" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -1)"
[[ "$latest_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || fail "could not determine the latest semantic version tag"
latest_version="${latest_tag#v}"
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

current_version="$(ruby -e '
  text = File.read(ARGV.fetch(0))
  match = text.match(/^\s*MARKETING_VERSION:\s*"([^"]+)"/)
  abort "MARKETING_VERSION not found" unless match
  puts match[1]
' "$project_file")"
current_version="$(normalize_version "$current_version")"
current_build="$(ruby -e '
  text = File.read(ARGV.fetch(0))
  match = text.match(/^\s*CURRENT_PROJECT_VERSION:\s*"([0-9]+)"/)
  abort "CURRENT_PROJECT_VERSION not found" unless match
  puts match[1]
' "$project_file")"

tap_dir="$(mktemp -d /tmp/launchdeck-release-tap.XXXXXX)"
git clone "$tap_repo" "$tap_dir/repository"
tap_cask="$tap_dir/repository/$tap_cask_path"
[[ -f "$tap_cask" ]] || fail "LaunchDeck cask not found: $tap_cask"
tap_version="$(ruby -e 'puts File.read(ARGV.fetch(0))[/^\s*version\s+"([^"]+)"/, 1]' "$tap_cask")"
tap_version="$(normalize_version "$tap_version")"

latest_tag_commit="$(git -C "$project_root" rev-list -n 1 "$latest_tag")"
release_exists=false
if gh release view "$latest_tag" --repo "$github_repo" >/dev/null 2>&1; then
  release_exists=true
fi

resume_release=false
if [[ "$current_version" == "$latest_version" && "$latest_tag_commit" == "$head_commit" ]] && \
   { [[ "$release_exists" != true ]] || [[ "$tap_version" != "$latest_version" ]]; }; then
  resume_release=true
  version="$latest_version"
  tag="$latest_tag"
  next_build="$current_build"
  echo "Resuming incomplete $tag publication."
else
  if [[ "$current_version" == "$latest_version" ]]; then
    version="$major.$minor.$((patch + 1))"
    next_build="$((current_build + 1))"
  else
    ruby -e '
      require "rubygems/version"
      abort "project version must be newer than the latest tag" unless
        Gem::Version.new(ARGV.fetch(0)) > Gem::Version.new(ARGV.fetch(1))
    ' "$current_version" "$latest_version"
    version="$current_version"
    next_build="$current_build"
    echo "Publishing the pre-bumped release version $version."
  fi
  tag="v$version"
  if git -C "$project_root" rev-parse "$tag" >/dev/null 2>&1 || \
     git -C "$project_root" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    fail "$tag already exists"
  fi
fi

if [[ -n "${LAUNCHDECK_RELEASE_DIR:-}" ]]; then
  release_dir="$LAUNCHDECK_RELEASE_DIR"
  mkdir -p "$release_dir"
else
  release_dir="$(mktemp -d "${TMPDIR:-/tmp}/launchdeck-release-$version.XXXXXX")"
fi
[[ "$release_dir" != "/" && "$release_dir" != "$project_root" ]] || fail "unsafe release directory: $release_dir"
derived_data="$release_dir/DerivedData"
app_path="$derived_data/Build/Products/Release/LaunchDeck.app"
notary_archive="$release_dir/LaunchDeck-$version-notary.zip"
archive="$release_dir/LaunchDeck-$version.zip"
checksum="$archive.sha256"
reuse_published_release=false
if [[ "$resume_release" == true && "$release_exists" == true ]]; then
  reuse_published_release=true
fi

if [[ "$reuse_published_release" == true ]]; then
  echo "Reusing the published $tag archive to finish the Homebrew update."
  gh release download "$tag" --repo "$github_repo" --pattern "$(basename "$archive")" --dir "$release_dir"
else
  [[ ! -e "$derived_data" ]] || fail "release directory already contains DerivedData: $derived_data"

  echo "Running LaunchDeck $version tests…"
  (cd "$project_root/Core" && swift test)
  (cd "$project_root" && xcodegen generate)
  xcodebuild \
    -project "$project_root/LaunchDeck.xcodeproj" \
    -scheme LaunchDeck \
    -configuration Debug \
    -derivedDataPath "$release_dir/TestDerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    test

  echo "Building and signing LaunchDeck ${version}…"
  xcodebuild \
    -project "$project_root/LaunchDeck.xcodeproj" \
    -scheme LaunchDeck \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$next_build" \
    build

  codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  entitlements="$(codesign -d --entitlements :- "$app_path" 2>/dev/null || true)"
  if grep -q 'com.apple.security.get-task-allow' <<<"$entitlements"; then
    fail "production signature contains com.apple.security.get-task-allow"
  fi
  codesign_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
  grep -q '^Timestamp=' <<<"$codesign_details" || fail "production signature has no secure timestamp"
  grep -q 'flags=.*runtime' <<<"$codesign_details" || fail "production signature does not enable hardened runtime"

  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_archive"
  notary_output="$(xcrun notarytool submit "$notary_archive" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_SPECIFIC_PASSWORD" \
    --wait)"
  printf '%s\n' "$notary_output"
  grep -q 'status: Accepted' <<<"$notary_output" || fail "Apple notarization did not return Accepted"

  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=4 "$app_path"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
fi
(
  cd "$release_dir"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

roundtrip_dir="$(mktemp -d /tmp/launchdeck-release-roundtrip.XXXXXX)"
ditto -x -k "$archive" "$roundtrip_dir"
codesign --verify --deep --strict --verbose=2 "$roundtrip_dir/LaunchDeck.app"
xcrun stapler validate "$roundtrip_dir/LaunchDeck.app"
spctl --assess --type execute --verbose=4 "$roundtrip_dir/LaunchDeck.app"

if [[ "$resume_release" != true ]]; then
  VERSION="$version" BUILD="$next_build" ruby -pi -e '
    gsub(/MARKETING_VERSION:\s*"[^"]+"/, %(MARKETING_VERSION: "#{ENV.fetch("VERSION")}"))
    gsub(/CURRENT_PROJECT_VERSION:\s*"[0-9]+"/, %(CURRENT_PROJECT_VERSION: "#{ENV.fetch("BUILD")}"))
  ' "$project_file"
  git -C "$project_root" add -- project.yml
  git -C "$project_root" diff --cached --check
  git -C "$project_root" commit -m "Prepare LaunchDeck $version (build $next_build)"
  git -C "$project_root" tag -a "$tag" -m "LaunchDeck $version"
  git -C "$project_root" push origin "HEAD:refs/heads/$release_branch" "refs/tags/$tag"
fi

archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
if gh release view "$tag" --repo "$github_repo" >/dev/null 2>&1; then
  published_digest="$(gh release view "$tag" --repo "$github_repo" --json assets --jq \
    ".assets[] | select(.name == \"$(basename "$archive")\") | .digest")"
  [[ "$published_digest" == "sha256:$archive_sha" ]] || \
    fail "existing GitHub Release has a different or missing archive digest"
  echo "GitHub Release $tag already contains the verified archive."
else
  gh release create "$tag" "$archive" "$checksum" \
    --repo "$github_repo" \
    --verify-tag \
    --generate-notes \
    --title "LaunchDeck $version"
fi

VERSION="$version" SHA="$archive_sha" ruby -pi -e '
  gsub(/^\s*version\s+"[^"]+"/, %(  version "#{ENV.fetch("VERSION")}"))
  gsub(/^\s*sha256\s+"[^"]+"/, %(  sha256 "#{ENV.fetch("SHA")}"))
' "$tap_cask"
ruby -c "$tap_cask"
brew style "$tap_cask"
git -C "$tap_dir/repository" add -- "$tap_cask_path"
git -C "$tap_dir/repository" diff --cached --check
if ! git -C "$tap_dir/repository" diff --cached --quiet; then
  git -C "$tap_dir/repository" commit -m "Update LaunchDeck to $version"
  git -C "$tap_dir/repository" push origin HEAD:main
fi

brew update
brew audit --cask --strict everettjf/tap/launchdeck
brew fetch --cask everettjf/tap/launchdeck
brew info --cask everettjf/tap/launchdeck

echo "LaunchDeck $version is signed, notarized, published, and available from Homebrew."
echo "Artifacts: $release_dir"
