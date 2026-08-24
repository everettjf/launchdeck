# LaunchDeck

<p align="center">
  <img src="LaunchDeck/Assets.xcassets/AppIcon.appiconset/appicon_512x512@2x.png" width="160" alt="LaunchDeck pixel-art rocket icon">
</p>

Repository: <https://github.com/everettjf/launchdeck>

[Website](https://xnu.app/launchdeck/) · [Discord](https://discord.gg/eGzEaP6TzR)

[![Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.gg/eGzEaP6TzR)

A private, local-first macOS launcher that combines Spotlight-style file discovery, Raycast-style actions, and LaunchBar-style workflows in one instant searchable index—with optional on-device intent search.

LaunchDeck is distributed directly with Developer ID signing through Homebrew and GitHub Releases. It no longer supports or ships through the Mac App Store. Its bundle identifier is `com.everettjf.launchdeck`; the former `com.xnu.startmyapp` identity is retired.

## Screenshot

![LaunchDeck Screenshot](screenshot.png)

## Highlights

- Auto-discover system and user apps and keep layout in sync
- Custom grid layout: drag to reorder, drag to create folders, favorite apps
- Unified local search across apps, files, folders, projects, settings, actions, approved Shortcuts, and recipes
- Instant Send captures Finder selections, browser URLs, selected text, and rich clipboard objects before LaunchDeck opens
- One keyboard-first Object → Action → Target navigator for single or multi-item operations, with one-step Undo
- Save a validated object/action/target chain as a reusable Recipe
- Search qualifiers such as `kind:file`, `path:Documents`, `ext:pdf`, and `app:Safari` filter before ranking
- Optional structured intent search (type `/`) that selects only validated local targets and registered actions
- Configurable local document/project roots with dependency, build, hidden, and sensitive-directory exclusions
- Deterministic local recipes with conditions, retries, optional steps, delays, output variables, execution logs, and action previews
- Declarative manifest v1/v2 extensions with integrity records, upgrade permission review, and no arbitrary code execution
- Native file actions for rename, move, duplicate, ZIP compression, Finder tags, and recoverable Trash deletion
- Window layouts covering halves, quarters, multiple displays, centering, maximizing, and frame restore
- Recently launched and most-launched sorting, with hidden apps support
- Menu bar entry + global hotkey to summon instantly

## Requirements

- macOS 26.0+
- Xcode 26.0+ and XcodeGen (local build)
- Intent search requires macOS 26, Apple Intelligence-capable hardware, and an available on-device model

## Install with Homebrew

```bash
brew install --cask everettjf/tap/launchdeck
```

Upgrade later with `brew upgrade --cask launchdeck`. The Homebrew build is signed with Developer ID and notarized by Apple. You can also download the latest ZIP from [GitHub Releases](https://github.com/everettjf/launchdeck/releases/latest).

## AI providers

LaunchDeck keeps Apple Foundation Models as its on-device default. Recipe Studio can also use an OpenAI-compatible chat-completions endpoint (including OpenAI, OpenRouter, DeepSeek, Ollama, and LM Studio) or the Anthropic Messages API.

Configure the protocol, endpoint, model, and API key under **Recipe Studio → External AI Provider**, then save and test the connection. API keys live in macOS Keychain and are never included in recipes, receipts, or AI history. Remote endpoints must use HTTPS; HTTP is accepted only for loopback endpoints. External routing remains opt-in through each recipe's model and data policy.

The Homebrew build does not depend on App Store-only PCC entitlements.

## Build Locally

1. Install XcodeGen: `brew install xcodegen`
2. Generate the project: `xcodegen generate`
3. Open `LaunchDeck.xcodeproj`, select the `LaunchDeck` scheme and run

Run the core logic tests with `cd Core && swift test`.

## Publish a Patch Release

With a clean `main` branch matching `origin/main`, export the Apple notarization credentials and run:

```bash
export APPLE_ID="developer@example.com"
export APPLE_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="YPV49M8592"
scripts/release-patch.sh
```

The script increments the latest semantic-version patch, updates the Xcode marketing/build versions, runs Core and app tests, creates a universal Developer ID-signed build, submits it to Apple for notarization, verifies the final ZIP, commits and tags the version, creates the GitHub Release, updates `everettjf/homebrew-tap`, and verifies the published cask. If publication stops after the tag is created, rerunning the script resumes that release instead of incrementing the patch again.

## Usage

- Type to search every indexed object without waiting for AI
- Press the global hotkey from Finder or a browser to Instant Send the current selection, then use Tab/Shift-Tab through Object → Action → Target
- Select multiple search results and press Command-K to run a compatible batch action; use the header Undo control to reverse file mutations
- Paste or search clipboard text, PNG images, and file selections after explicitly enabling local clipboard history
- Start with `/` to describe an intent (e.g. `/edit an image`); local results remain visible while AI ranks structured target/action candidates
- Select an elevated action to review its exact target, ordered steps, permissions, and risk before confirming
- Drag apps to reorder, drag onto apps to create folders
- Adjust sorting, grid size, system apps visibility, and hotkey in Settings

## Settings Overview

- Show system apps / recent launches / hidden apps
- Sort order (custom / name / most launched / recently launched)
- Grid density (compact / comfortable / spacious)
- Menu bar icon and global hotkey
- Apple Intelligence availability status
- Explicitly approved Shortcuts with confirmation before every run
- Search roots for local files, folders, Git repositories, and Xcode projects
- Local recipes assembled from apps, projects, Terminal locations, and approved Shortcuts
- Recipe templates, reusable variables, and ordered step editing
- Privacy-first clipboard history, snippets, window actions, editable Quicklinks, and local learning
- Declarative extension install/uninstall with permission summaries
- Local launch, action, and recent-document history reset

## Privacy and action safety

Application indexes, organization, recipes, launch history, recent documents, and action records stay on the Mac. LaunchDeck actions are typed and validated: AI output cannot invent target or action identifiers, file/directory types are checked before execution, system settings use fixed destinations, and Shortcuts—including those inside imported recipes—must be explicitly approved. Elevated actions show a full preview and require confirmation.

| Local data | Default / retention | Reset |
| --- | --- | --- |
| Clipboard text, images, and file references | Disabled; when enabled, 200 entries; 20,000 characters, 5 MB image data, or 100 file paths per entry; user-selected 1/7/30-day retention | Clipboard clear or unified behavioral-data reset |
| Recent documents | Up to 30 entries | Unified behavioral-data reset |
| Action history | Latest 50 actions | Unified behavioral-data reset |
| Recipe execution logs | Latest 50 executions | Recipe log clear or unified behavioral-data reset |
| Search learning and recent queries | Local until reset | Unified behavioral-data reset |

Clipboard monitoring excludes supported password managers and user-configured bundle identifiers. Accessibility is requested only for explicit window commands and is not used to inspect window contents.

## Performance benchmark

Run `cd Core && swift run -c release application-index-benchmark --apps 100000`. The command emits JSON covering cold discovery, incremental refresh, app and unified-index construction, qualified and fuzzy-search p50/p95 latency, intent-candidate retrieval, resident memory, and index memory delta. CI validates it against `Benchmarks/search-thresholds-100k.json`.

## Project Structure

```
LaunchDeck/
├── Models/                      # Preferences and shortcut models
├── Services/                    # Discovery/cache/persistence/hotkey/window/search controllers
├── Views/                       # SwiftUI views
├── Extensions/                  # Extensions
├── AppState.swift               # Orchestrator: discovery, favorites, recents, launch
└── LaunchDeckApp.swift          # App entry
Core/                            # LaunchDeckCore SwiftPM package (pure logic + tests)
├── Sources/LaunchDeckCore/      # Models, discovery, ranking, layout sync, sorting
├── Sources/ApplicationIndexBenchmark/
└── Tests/LaunchDeckCoreTests/
```

The Xcode project is generated from `project.yml` by XcodeGen; `LaunchDeck.xcodeproj` is not committed.

## Contributing

Issues and PRs are welcome. Please include use cases or repro steps to help pinpoint problems quickly.

## License

MIT

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=everettjf/launchdeck&type=Date)](https://star-history.com/#everettjf/launchdeck&Date)
