# LaunchDeck Declarative Extensions

Manifest schema versions 1 and 2 add commands without loading or executing third-party code. Install a JSON manifest from LaunchDeck Settings → Extensions.

## Manifest

Required top-level fields are `schemaVersion`, a reverse-domain `id`, display `name`, semantic `version`, declared `permissions`, and at least one command.

Schema v2 optionally adds `minimumLaunchDeckVersion` and `publisher`. LaunchDeck records the installed manifest SHA-256 and installation date, rejects downgrades and incompatible minimum versions, and requires an explicit confirmation when an update adds permissions. Schema v1 remains fully supported.

Supported command kinds:

- `quicklink`: requires `network`, a one-word `keyword`, and an HTTP(S) URL containing `{query}`.
- `openURL`: requires `network` and a fixed HTTP(S) URL.
- `staticText`: copies fixed text and requires no permission.

Permissions are closed to `network`, `files`, and `processes`. Manifest v1 and v2 implement only declarative network navigation and text copying; declaring file or process access does not grant executable capability.

Invalid schemas, invalid semantic versions, duplicate command identifiers, undeclared network access, non-web URLs, and malformed templates are rejected before installation. Each extension is stored in its own local directory and can be disabled by uninstalling it from Settings.

See the three examples in `Examples/Extensions`.
