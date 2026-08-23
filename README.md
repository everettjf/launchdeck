# LaunchDeck

Repository: <https://github.com/everettjf/launchdeck>

[Website](https://xnu.app/launchdeck/) · [Discord](https://discord.gg/eGzEaP6TzR)

[![Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.gg/eGzEaP6TzR)

A private, local-first macOS launcher that combines Spotlight-style file discovery, Raycast-style actions, and LaunchBar-style workflows in one instant searchable index—with optional on-device intent search.

LaunchDeck is configured for direct Developer ID distribution rather than the Mac App Store.

## Screenshot

![LaunchDeck Screenshot](screenshot.png)

## Highlights

- Auto-discover system and user apps and keep layout in sync
- Custom grid layout: drag to reorder, drag to create folders, favorite apps
- Unified local search across apps, files, folders, projects, settings, actions, approved Shortcuts, and recipes
- Optional structured intent search (type `/`) that selects only validated local targets and registered actions
- Configurable local document/project roots with dependency, build, hidden, and sensitive-directory exclusions
- Deterministic local recipes with create/edit/import/export and step-by-step action previews
- Recently launched and most-launched sorting, with hidden apps support
- Menu bar entry + global hotkey to summon instantly

## Requirements

- macOS 15.0+
- Xcode 26.0+ and XcodeGen (local build)
- Intent search requires macOS 26, Apple Intelligence-capable hardware, and an available on-device model

## Install with Homebrew

```bash
brew install --cask everettjf/tap/launchdeck
```

Upgrade later with `brew upgrade --cask launchdeck`. The Homebrew build is signed with Developer ID and notarized by Apple. You can also download the latest ZIP from [GitHub Releases](https://github.com/everettjf/launchdeck/releases/latest).

## Build Locally

1. Install XcodeGen: `brew install xcodegen`
2. Generate the project: `xcodegen generate`
3. Open `LaunchDeck.xcodeproj`, select the `LaunchDeck` scheme and run

Run the core logic tests with `cd Core && swift test`.

## Usage

- Type to search every indexed object without waiting for AI
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
- Local launch, action, and recent-document history reset

## Privacy and action safety

Application indexes, organization, recipes, launch history, recent documents, and the latest 50 action records stay on the Mac. Recent documents retain at most 30 entries. Settings includes a single reset for launch, action, and recent-document history. LaunchDeck actions are typed and validated: AI output cannot invent target or action identifiers, file/directory types are checked before execution, system settings use fixed destinations, and Shortcuts—including those inside imported recipes—must be explicitly approved. Elevated actions show a full preview and require confirmation.

## Performance benchmark

Run `cd Core && swift run -c release application-index-benchmark --apps 5000`. The command emits JSON covering cold discovery, incremental refresh, app and unified-index construction, intent-candidate retrieval, and fuzzy-search p50/p95 latency.

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
