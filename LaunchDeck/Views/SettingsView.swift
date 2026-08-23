import AppKit
import SwiftUI
import LaunchDeckCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var appState: AppState
    @State private var shortcutName = ""
    @State private var presentedRecipeSheet: RecipeSheet?
    @State private var operationError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show System Applications", isOn: preferences.showSystemAppsBinding)
                Picker("Sort Order", selection: $preferences.sortOption) {
                    ForEach(AppPreferences.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle("Show Recent Launches", isOn: $preferences.showRecentApps)
                Toggle("Show Hidden Applications", isOn: $preferences.showHiddenApps)
            } header: { Text("General") }

            Section {
                Picker("Tile Size", selection: $preferences.gridScale) {
                    ForEach(AppPreferences.GridScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("Appearance") }

            Section {
                Toggle("Show Menu Bar Icon", isOn: $preferences.showMenuBarIcon)
                Toggle("Enable Global Shortcut", isOn: $preferences.isGlobalShortcutEnabled)
                if preferences.isGlobalShortcutEnabled {
                    ShortcutRecorderView(shortcut: $preferences.globalShortcut)
                    Text("Press Escape to cancel. Requires at least one modifier key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Quick Access") }

            Section {
                HStack {
                    Text("Apple Intelligence")
                    Spacer()
                    availabilityView
                }
                if case .unavailable(.appleIntelligenceNotEnabled) = appState.intentSearchAvailability {
                    Button("Open Apple Intelligence Settings") {
                        appState.requestAction(.openSystemSettings(destination: .appleIntelligence))
                    }
                }
            } header: { Text("Intent Search") }
              footer: { Text(availabilityMessage).font(.caption) }

            Section {
                HStack {
                    TextField("Exact shortcut name", text: $shortcutName)
                    Button("Allow", action: addShortcut)
                        .disabled(shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(preferences.approvedShortcuts, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Run") { appState.requestAction(.runShortcut(name: name)) }
                        Button("Remove", role: .destructive) {
                            preferences.approvedShortcuts.removeAll { $0 == name }
                        }
                    }
                }
            } header: { Text("Approved Shortcuts") }
              footer: {
                  Text("Only shortcuts explicitly listed here can be requested. LaunchDeck asks for confirmation before every run.")
                      .font(.caption)
              }

            Section {
                ForEach(preferences.indexedRootPaths, id: \.self) { path in
                    HStack {
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", role: .destructive) { appState.removeIndexedRoot(path) }
                    }
                }
                HStack {
                    Button("Add Folder…", action: chooseIndexedRoot)
                    Button("Refresh Index") { appState.refreshLocalContent() }
                    Spacer()
                    Text("\(appState.indexedItems.count) items").foregroundStyle(.secondary)
                }
            } header: { Text("Local Search Index") }
              footer: { Text("Indexes common documents, Git repositories, and Xcode projects. Dependency, build, hidden, and Library folders are skipped.").font(.caption) }

            Section {
                ForEach(appState.recipeStore.recipes) { recipe in
                    HStack {
                        VStack(alignment: .leading) { Text(recipe.name); Text("\(recipe.steps.count) steps").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Run") {
                            if recipe.variables.isEmpty { run(recipe, values: [:]) }
                            else { presentedRecipeSheet = .run(recipe) }
                        }
                        Button("Edit") { presentedRecipeSheet = .edit(recipe) }
                        Button("Remove", role: .destructive) { appState.recipeStore.remove(id: recipe.id) }
                    }
                }
                HStack {
                    Button("New Recipe") { presentedRecipeSheet = .edit(Recipe(name: "New Recipe", steps: [])) }
                    Button("Import…", action: importRecipes)
                    Button("Export…", action: exportRecipes).disabled(appState.recipeStore.recipes.isEmpty)
                }
            } header: { Text("Recipes") }
              footer: { Text("Recipes are deterministic local action sequences. Every run shows all steps before confirmation.").font(.caption) }

            Section {
                Button("Clear Launch and Action History", role: .destructive) {
                    appState.clearPrivateHistory()
                }
            } header: { Text("Privacy") }
              footer: {
                  Text("History stays on this Mac. Clearing it does not remove favorites, folders, or approved shortcuts.")
                      .font(.caption)
              }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .sheet(item: $presentedRecipeSheet) { sheet in
            switch sheet {
            case .edit(let recipe):
                RecipeEditorView(recipe: recipe,
                                 applications: appState.allApps(),
                                 approvedShortcuts: preferences.approvedShortcuts) { updated in
                    do { try appState.recipeStore.save(updated); return true }
                    catch { operationError = error.localizedDescription; return false }
                }
            case .run(let recipe):
                RecipeRunView(recipe: recipe) { values in run(recipe, values: values) }
            }
        }
        .alert("Settings Action Failed", isPresented: operationErrorBinding) {
            Button("OK") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder
    private var availabilityView: some View {
        switch appState.intentSearchAvailability {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(.modelNotReady):
            Label("Downloading", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
        case .unavailable(.appleIntelligenceNotEnabled):
            Label("Not Enabled", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unavailable:
            Label("Unavailable", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var availabilityMessage: String {
        switch appState.intentSearchAvailability {
        case .checking: return "Checking the on-device model."
        case .available: return "Type '/' before a goal to rank installed apps with on-device Apple Intelligence."
        case .unavailable(.requiresMacOS26): return "Intent search requires macOS 26. Fast local search remains fully available."
        case .unavailable(.deviceNotEligible): return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings to use intent search."
        case .unavailable(.modelNotReady): return "The on-device model is downloading or not ready."
        case .unavailable(.unknown): return "Apple Intelligence is currently unavailable."
        }
    }

    private func addShortcut() {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !preferences.approvedShortcuts.contains(name) else { return }
        preferences.approvedShortcuts.append(name)
        shortcutName = ""
    }

    private func chooseIndexedRoot() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(appState.addIndexedRoot)
    }

    private func importRecipes() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try appState.recipeStore.importData(Data(contentsOf: url)) }
        catch { operationError = error.localizedDescription }
    }

    private func exportRecipes() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "LaunchDeck Recipes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try appState.recipeStore.exportData().write(to: url, options: .atomic) }
        catch { operationError = error.localizedDescription }
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
    }

    private func run(_ recipe: Recipe, values: [String: String]) {
        switch RecipeVariableResolver.resolve(steps: recipe.steps, variables: recipe.variables, values: values) {
        case .resolved(let steps):
            appState.requestAction(.runRecipe(identifier: recipe.id, name: recipe.name, steps: steps))
        case .missing(let names):
            operationError = "Enter values for: \(names.joined(separator: ", "))."
        }
    }
}

private enum RecipeSheet: Identifiable {
    case edit(Recipe)
    case run(Recipe)

    var id: String {
        switch self {
        case .edit(let recipe): "edit-\(recipe.id)"
        case .run(let recipe): "run-\(recipe.id)"
        }
    }
}

private struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe
    let applications: [DiscoveredApp]
    let approvedShortcuts: [String]
    let onSave: (Recipe) -> Bool
    @State private var stepKind = StepKind.project
    @State private var stepValue = ""
    @State private var selectedApplicationIdentifier = ""
    @State private var selectedShortcut = ""
    @State private var variableName = ""

    enum StepKind: String, CaseIterable, Identifiable { case application, project, terminal, shortcut; var id: String { rawValue } }

    init(recipe: Recipe, applications: [DiscoveredApp], approvedShortcuts: [String], onSave: @escaping (Recipe) -> Bool) {
        _recipe = State(initialValue: recipe)
        self.applications = applications
        self.approvedShortcuts = approvedShortcuts
        self.onSave = onSave
        _selectedApplicationIdentifier = State(initialValue: applications.first?.identifier ?? "")
        _selectedShortcut = State(initialValue: approvedShortcuts.first ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recipe").font(.title2.weight(.semibold))
                Spacer()
                Menu("Use Template") {
                    ForEach(RecipeTemplateCatalog.templates) { template in
                        Button(template.name) { apply(template) }
                    }
                }
            }
            TextField("Name", text: $recipe.name)
            List {
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    HStack {
                        Text(step.summary)
                        Spacer()
                        Button { moveStep(from: index, by: -1) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                            .accessibilityLabel("Move step up")
                        Button { moveStep(from: index, by: 1) } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless).disabled(index == recipe.steps.count - 1)
                            .accessibilityLabel("Move step down")
                    }
                }
                    .onDelete { recipe.steps.remove(atOffsets: $0) }
            }.frame(height: 180)
            HStack {
                Picker("Step", selection: $stepKind) { ForEach(StepKind.allCases) { Text($0.rawValue.capitalized).tag($0) } }.frame(width: 150)
                stepEditor
                Button("Add", action: addStep).disabled(!canAddStep)
            }
            GroupBox("Variables") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($recipe.variables) { $variable in
                        HStack {
                            TextField("Name", text: $variable.name)
                            TextField("Default value (optional)", text: $variable.defaultValue)
                            Button("Remove", role: .destructive) {
                                recipe.variables.removeAll { $0.id == variable.id }
                            }
                        }
                    }
                    HStack {
                        TextField("Variable name", text: $variableName)
                        Button("Add Variable", action: addVariable)
                            .disabled(!canAddVariable)
                    }
                    Text("Use variables in step values as {{variableName}}.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { if onSave(recipe) { dismiss() } }
                    .disabled(RecipeValidation.error(for: recipe) != nil)
            }
        }.padding(24).frame(width: 700)
    }

    @ViewBuilder private var stepEditor: some View {
        switch stepKind {
        case .application:
            Picker("Application", selection: $selectedApplicationIdentifier) {
                ForEach(applications) { Text($0.name).tag($0.identifier) }
            }
        case .shortcut:
            Picker("Shortcut", selection: $selectedShortcut) {
                ForEach(approvedShortcuts, id: \.self) { Text($0).tag($0) }
            }
        case .project, .terminal:
            TextField("Path", text: $stepValue)
            Button("Choose…", action: choosePath)
        }
    }

    private var canAddStep: Bool {
        switch stepKind {
        case .application: !selectedApplicationIdentifier.isEmpty
        case .shortcut: !selectedShortcut.isEmpty
        case .project, .terminal: !stepValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func addStep() {
        let value = stepValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stepKind {
        case .application:
            guard let app = applications.first(where: { $0.identifier == selectedApplicationIdentifier }) else { return }
            recipe.steps.append(.openApplication(identifier: app.identifier, name: app.name))
        case .project: recipe.steps.append(.openProject(path: value))
        case .terminal: recipe.steps.append(.openTerminal(directory: value))
        case .shortcut: recipe.steps.append(.runShortcut(name: selectedShortcut))
        }
        stepValue = ""
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = stepKind == .project
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        stepValue = url.path
    }

    private var canAddVariable: Bool {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecipeVariableResolver.placeholders(in: "{{\(name)}}").first == name
            && !recipe.variables.contains { $0.name == name }
    }

    private func addVariable() {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddVariable else { return }
        recipe.variables.append(RecipeVariable(name: name))
        variableName = ""
    }

    private func moveStep(from source: Int, by offset: Int) {
        let destination = offset > 0 ? source + offset + 1 : source + offset
        recipe.steps = RecipeStepOrder.moving(recipe.steps, from: source, to: destination)
    }

    private func apply(_ template: RecipeTemplate) {
        recipe.name = template.name
        recipe.variables = template.variables
        recipe.steps = template.steps
    }
}

struct RecipeRunView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let onRun: ([String: String]) -> Void
    @State private var values: [String: String]
    @State private var missingNames: [String] = []

    init(recipe: Recipe, onRun: @escaping ([String: String]) -> Void) {
        self.recipe = recipe
        self.onRun = onRun
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: recipe.variables.map { ($0.name, $0.defaultValue) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run \(recipe.name)").font(.title2.weight(.semibold))
            Text("Enter values before reviewing the complete action preview.")
                .foregroundStyle(.secondary)
            Form {
                ForEach(recipe.variables) { variable in
                    TextField(variable.name, text: valueBinding(for: variable.name))
                }
            }
            if !missingNames.isEmpty {
                Text("Required: \(missingNames.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Review and Run") { submit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func valueBinding(for name: String) -> Binding<String> {
        Binding(get: { values[name, default: ""] }, set: { values[name] = $0 })
    }

    private func submit() {
        if case .missing(let names) = RecipeVariableResolver.resolve(
            steps: recipe.steps, variables: recipe.variables, values: values
        ) {
            missingNames = names
            return
        }
        let submittedValues = values
        dismiss()
        DispatchQueue.main.async { onRun(submittedValues) }
    }
}

#Preview {
    let preferences = AppPreferences()
    SettingsView()
        .environmentObject(preferences)
        .environmentObject(AppState(preferences: preferences))
}
