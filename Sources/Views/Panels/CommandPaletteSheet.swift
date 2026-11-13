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
                    Section(preferences.tr("Lệnh IDE (Commands)", "IDE Commands", zh: "IDE 命令", ja: "IDE コマンド", ko: "IDE 명령", ru: "Команды IDE", es: "Comandos del IDE")) {
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
                    Section(preferences.tr("Mở Nhanh File (Quick Open)", "Quick Open Files", zh: "快速打开文件", ja: "クイックオープン", ko: "빠른 파일 열기", ru: "Быстрое открытие", es: "Apertura Rápida")) {
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: preferences.tr("Gõ tên lệnh hoặc tên file...", "Type a command or file name..."))
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(preferences.tr("Đóng", "Close", zh: "关闭", ja: "閉じる", ko: "닫기", ru: "Закрыть", es: "Cerrar")) { dismiss() }
                }
            }
        }
    }
}
