# Foundation Models Guide for StartMyApp

[![Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.com/invite/eGzEaP6TzR)

This document tracks how StartMyApp integrates Apple Foundation Models (Apple Intelligence), with a focus on semantic search and future extensions.

## Core Capabilities

- Text generation and understanding
- Summarization and structured extraction
- Structured data generation (Guided Generation)
- Custom tool calling (Tool Calling)

## Integration Points in StartMyApp

- Semantic search entry: `StartMyApp/ContentView.swift` (type `/` to trigger AI search)
- AI search logic: `StartMyApp/Services/SemanticSearchService.swift`
- Availability + status UI: `StartMyApp/Views/SettingsView.swift`

## Model Availability Check

Always check availability before calling the model. Availability depends on device support, system settings, and model readiness.

```swift
struct GenerativeView: View {
    private var model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            Text("Model is available")
        case .unavailable(.deviceNotEligible):
            Text("Device not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            Text("Please enable Apple Intelligence in Settings")
        case .unavailable(.modelNotReady):
            Text("Model is downloading or not ready")
        case .unavailable(let other):
            Text("Model unavailable: \(other)")
        }
    }
}
```

## Session Guidelines

- Single-turn: create a new `LanguageModelSession` each time
- Multi-turn: reuse the same session to preserve context
- A session can handle only one request at a time; check `isResponding` when needed

```swift
let session = LanguageModelSession()
let response = try await session.respond(to: "What is a good month to visit Paris?")
print(response.content)
```

## Guided Generation (Structured Output)

Use `@Generable` to define structured types and avoid manual string parsing.

```swift
@Generable(description: "Basic profile information about a cat")
struct CatProfile {
    var name: String

    @Guide(description: "The age of the cat", .range(0...20))
    var age: Int

    @Guide(description: "A one sentence profile about the cat's personality")
    var profile: String
}

let response = try await session.respond(
    to: "Generate a cute rescue cat",
    generating: CatProfile.self
)

print(response.content.name)
```

Note: Always use `response.content` when printing values, not `response.output`.

## Tool Calling (Custom Tools)

When external data or business logic is needed, connect the model and your system via Tool calling.

```swift
struct RecipeSearchTool: Tool {
    struct Arguments: Codable {
        var searchTerm: String
        var numberOfResults: Int
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let recipes = await searchRecipes(term: arguments.searchTerm,
                                         limit: arguments.numberOfResults)
        return .string(recipes.map { "- \($0.name): \($0.description)" }
            .joined(separator: "\n"))
    }
}

let session = LanguageModelSession(tools: [RecipeSearchTool()])
let response = try await session.respond(to: "Find me some pasta recipes")
```

## Snapshot Streaming (Structured Streaming Output)

Foundation Models can stream structured output using snapshots.

- A snapshot is a partially generated struct with all optional fields
- `@Generable` automatically produces the corresponding `PartiallyGenerated` type
- Great for SwiftUI: update state on each snapshot for progressive rendering

```swift
@Generable
struct TripIdeas {
    @Guide(description: "Ideas for upcoming trips")
    var ideas: [String]
}

let stream = session.streamResponse(
    to: "What are some exciting trip ideas for the upcoming year?",
    generating: TripIdeas.self
)

for try await partial in stream {
    print(partial)
}
```

## Limits and Recommendations

- A single session has a 4,096-token context window
- Instructions and outputs consume the window; split large inputs
- Use `GenerationOptions` to balance stability and creativity
- Use `session.transcript` to inspect model actions and tool calls

## References

- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/FoundationModels/generating-swift-data-structures-with-guided-generation)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling)
- [Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/technologies/generative-ai)

## Product and Performance Priorities

- Make the README and onboarding state the concrete advantage over Spotlight, Raycast, and LaunchBar in one sentence.
- Add repeatable launch-index benchmarks covering cold start, application discovery, search latency, semantic-search opt-in, and large installed-app sets.
- Keep ordinary fuzzy search instant and fully functional when AI search is unavailable or disabled.
- Treat app launch history as private local behavioral data; document retention and provide a clear reset action.
