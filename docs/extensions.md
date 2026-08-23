# LaunchDeck Declarative Extensions

Manifest schema version 1 adds commands without loading or executing third-party code. Install a JSON manifest from LaunchDeck Settings → Extensions.

## Manifest

Required top-level fields are `schemaVersion`, a reverse-domain `id`, display `name`, semantic `version`, declared `permissions`, and at least one command.

Supported command kinds:

- `quicklink`: requires `network`, a one-word `keyword`, and an HTTP(S) URL containing `{query}`.
- `openURL`: requires `network` and a fixed HTTP(S) URL.
- `staticText`: copies fixed text and requires no permission.

Permissions are closed to `network`, `files`, and `processes`. Manifest v1 implements only declarative network navigation and text copying; declaring file or process access does not grant executable capability.

Invalid schemas, duplicate command identifiers, undeclared network access, non-web URLs, and malformed templates are rejected before installation. Each extension is stored in its own local directory and can be disabled by uninstalling it from Settings.

See the three examples in `Examples/Extensions`.
