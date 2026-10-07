import AppKit
import Combine
import SwiftUI
import LaunchDeckCore

struct NewFolderSheet: View {
    @Binding var isPresented: Bool
    @Binding var folderName: String
    var onCreate: (String) -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Folder")
                .font(.title2.weight(.semibold))

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit(commit)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Create") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            if folderName.isEmpty {
                folderName = defaultFolderName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    private func commit() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        folderName = ""
        isPresented = false
    }

    private var defaultFolderName: String {
        "New Folder"
    }
}
