import SwiftUI

public struct CommandPaletteSheet: View {
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    var commands: [(title: String, icon: String, action: () -> Void)]
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    public init(
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        commands: [(title: String, icon: String, action: () -> Void)]
    ) {
        self.workspace = workspace
        self.preferences = preferences
        self.commands = commands
    }

    public var body: some View {
        let allFiles = workspace.flattenFiles(in: workspace.fileTree)
        let filteredCommands = commands.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
        let filteredFiles = allFiles.filter {
            query.isEmpty || workspace.relativePath(for: $0).localizedCaseInsensitiveContains(query)
        }

        NavigationStack {
            List {
                if !filteredCommands.isEmpty {
                    Section("Lệnh IDE (Commands)") {
                        ForEach(Array(filteredCommands.enumerated()), id: \.offset) { _, cmd in
                            Button {
                                dismiss()
                                cmd.action()
                            } label: {
                                Label(cmd.title, systemImage: cmd.icon)
                            }
                        }
                    }
                }

                if !filteredFiles.isEmpty {
                    Section("Mở Nhanh File (Quick Open)") {
                        ForEach(filteredFiles, id: \.path) { url in
                            Button {
                                workspace.openFile(at: url)
                                dismiss()
                            } label: {
                                Label(workspace.relativePath(for: url), systemImage: CodeLanguage.detect(from: url).systemIcon)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Gõ tên lệnh hoặc tên file...")
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
