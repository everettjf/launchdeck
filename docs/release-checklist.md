# LaunchDeck Release Checklist

## Automated gates

- Core SwiftPM tests pass.
- LaunchDeck app tests pass.
- Debug and universal Release builds pass.
- Release metadata and `launchdeck://` URL scheme validate.
- The 10,000-application search benchmark stays within tracked thresholds.
- `git diff --check` passes.

## Manual macOS matrix

- Apple Silicon and Intel launch/install smoke tests.
- Apple Intelligence available, disabled, and unavailable states.
- Clipboard opt-in, retention, excluded app, and unified reset behavior.
- Accessibility denied/granted/revoked behavior.
- Window halves, quarters, next/previous display, and restore on one and two displays.
- File rename, move, duplicate, ZIP, tags, and Trash recovery.
- Recipe dry run, condition skip, retry, optional failure, dynamic output, delay, and logs.
- Extension v1 install, v2 install, upgrade, permission expansion, downgrade rejection, and uninstall.
- VoiceOver navigation through search, filters, action panel, Settings, and confirmation previews.

## Distribution

- Developer ID signature has Hardened Runtime and secure timestamp.
- Apple notarization is accepted and stapled.
- ZIP round-trip passes codesign, stapler, and Gatekeeper checks.
- GitHub Release and Homebrew cask checksums match.
