import SwiftUI
import UIKit

public struct CPTestCaseItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var input: String
    public var expectedOutput: String
    public var actualOutput: String = ""
    public var passed: Bool? = nil
    public var durationMs: Int? = nil

    public init(id: UUID = UUID(), input: String, expectedOutput: String) {
        self.id = id
        self.input = input
        self.expectedOutput = expectedOutput
    }
}

public struct DeveloperPowerToolsSheet: View {
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    private enum ToolTab: Int, CaseIterable {
        case cpJudge = 0
        case miniPostman = 1
        case envEditor = 2
        case colorClipboard = 3
    }

    @State private var selectedTab: ToolTab = .cpJudge

    // 1. CP Test Judge State
    @State private var testCases: [CPTestCaseItem] = [
        CPTestCaseItem(input: "5\n42 7 19 88 3\n", expectedOutput: "3 7 19 42 88")
    ]
    @State private var isJudging: Bool = false

    // 2. Mini Postman State
    @State private var httpMethod: String = "GET"
    @State private var requestURL: String = "https://httpbin.org/get"
    @State private var requestHeadersText: String = "Content-Type: application/json"
    @State private var requestBodyText: String = "{\n  \"app\": \"3012\"\n}"
    @State private var responseStatusBadge: String = ""
    @State private var responseLatencyMs: Int = 0
    @State private var responseBody: String = ""
    @State private var isSendingHTTP: Bool = false
    @State private var postmanNotice: String? = nil

    // 3. .env Visual Editor State
    @State private var envPairs: [(id: UUID, key: String, value: String, hidden: Bool)] = []
    @State private var newEnvKey: String = ""
    @State private var newEnvValue: String = ""
    @State private var envSaveNotice: String? = nil

    // 4. Color Picker & Clipboard History State
    @State private var pickedColor: Color = .blue
    @State private var clipNotes: [String] = []
    @State private var newClipText: String = ""

    public init(
        workspace: WorkspaceManager,
        runner: CodeRunnerService,
        sshService: SSHWorkspaceService,
        preferences: EditorPreferences
    ) {
        self.workspace = workspace
        self.runner = runner
        self.sshService = sshService
        self.preferences = preferences
    }

    public var body: some View {
        CompatibleNavigationContainer {
            VStack(spacing: 0) {
                Picker("Developer Tool", selection: $selectedTab) {
                    Text("CP Judge").tag(ToolTab.cpJudge)
                    Text("API Test").tag(ToolTab.miniPostman)
                    Text(".env").tag(ToolTab.envEditor)
                    Text(preferences.tr("Màu & Clip", "Color & Clip")).tag(ToolTab.colorClipboard)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                switch selectedTab {
                case .cpJudge:
                    cpJudgeView
                case .miniPostman:
                    miniPostmanView
                case .envEditor:
                    envEditorView
                case .colorClipboard:
                    colorClipboardView
                }
            }
            .navigationTitle(preferences.tr("Công cụ Lập trình Viên", "Developer Power Tools"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
            .onAppear {
                loadEnvPairs()
                loadClipboardHistory()
            }
        }
    }

    // MARK: - 1. Competitive Programming Multi-Test Judge
    private var cpJudgeView: some View {
        Form {
            Section {
                if let tab = workspace.activeTab {
                    HStack {
                        Label(tab.title, systemImage: "doc.text")
                        Spacer()
                        Text(tab.language.rawValue)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(preferences.tr("Hãy mở 1 file code (C++, Python, Go...) để chấm test.", "Open a code file to judge test cases."))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button {
                        testCases.append(CPTestCaseItem(input: "", expectedOutput: ""))
                    } label: {
                        Label(preferences.tr("+ Thêm Test", "+ Add Test"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        Task { await runAllTests() }
                    } label: {
                        HStack {
                            if isJudging { ProgressView().scaleEffect(0.8) }
                            Text(preferences.tr("Chấm toàn bộ (\(testCases.count))", "Run All Tests (\(testCases.count))"))
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isJudging || workspace.activeTab == nil)
                }
            }

            ForEach(Array(testCases.enumerated()), id: \.element.id) { idx, tc in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Test #\(idx + 1)")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if let ms = tc.durationMs {
                                Text("\(ms) ms")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            if let passed = tc.passed {
                                Text(passed ? "AC" : "WA")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background((passed ? Color.green : Color.red).opacity(0.2))
                                    .foregroundColor(passed ? .green : .red)
                                    .clipShape(Capsule())
                            }
                            Button(role: .destructive) {
                                testCases.removeAll { $0.id == tc.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Input (stdin):")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextEditor(text: $testCases[idx].input)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 54)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

                        Text("Expected Output:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextEditor(text: $testCases[idx].expectedOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 54)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

                        if !tc.actualOutput.isEmpty {
                            Text("Actual Output:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(tc.actualOutput)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func runAllTests() async {
        guard let tab = workspace.activeTab else { return }
        isJudging = true
        defer { isJudging = false }

        for idx in testCases.indices {
            let stdinStr = testCases[idx].input
            let res = await runner.executeCodeSnapshot(
                code: tab.content,
                language: tab.language,
                fileName: tab.title,
                stdin: stdinStr,
                sshService: sshService,
                bypassCache: false
            )
            let normActual = normalizeCPOutput(res.output)
            let normExpected = normalizeCPOutput(testCases[idx].expectedOutput)
            testCases[idx].actualOutput = res.output
            testCases[idx].durationMs = res.durationMs
            testCases[idx].passed = !res.failed && (normActual == normExpected)
        }
    }

    private func normalizeCPOutput(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 2. Mini Postman REST API Tester
    private var miniPostmanView: some View {
        Form {
            Section(preferences.tr("Yêu cầu HTTP", "HTTP Request")) {
                Picker("Method", selection: $httpMethod) {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                TextField("https://api.example.com/v1/...", text: $requestURL)
                    .font(.system(size: 12.5, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Headers (Key: Value per line):")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextEditor(text: $requestHeadersText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 54)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                }

                if httpMethod != "GET" && httpMethod != "DELETE" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body (JSON / Raw):")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextEditor(text: $requestBodyText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 75)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    }
                }

                Button {
                    Task { await sendHTTPRequest() }
                } label: {
                    HStack {
                        if isSendingHTTP { ProgressView().scaleEffect(0.8) }
                        Text(preferences.tr("Gửi Request", "Send Request"))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSendingHTTP)
            }

            if !responseStatusBadge.isEmpty || !responseBody.isEmpty {
                Section(preferences.tr("Phản hồi (Response)", "HTTP Response")) {
                    HStack {
                        Text(responseStatusBadge)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(responseStatusBadge.hasPrefix("2") ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundColor(responseStatusBadge.hasPrefix("2") ? .green : .orange)
                            .clipShape(Capsule())
                        Spacer()
                        Text("\(responseLatencyMs) ms")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Button(preferences.tr("Copy JSON", "Copy")) {
                            UIPasteboard.general.string = responseBody
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(responseBody)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 140, maxHeight: 260)
                }
            }

            Section(preferences.tr("Xuất Code 1-Chạm", "1-Tap Client Codegen")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Copy cURL") {
                            UIPasteboard.general.string = generateCurlCode()
                            postmanNotice = "Copied cURL command."
                        }
                        .buttonStyle(.bordered)
                        Button("Copy JS fetch") {
                            UIPasteboard.general.string = generateJSFetchCode()
                            postmanNotice = "Copied JavaScript fetch()."
                        }
                        .buttonStyle(.bordered)
                        Button("Copy Python") {
                            UIPasteboard.general.string = generatePythonRequestsCode()
                            postmanNotice = "Copied Python requests code."
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let postmanNotice {
                    Text(postmanNotice)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func sendHTTPRequest() async {
        guard let url = URL(string: requestURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            responseStatusBadge = "INVALID URL"
            responseBody = "Kiểm tra lại định dạng URL (http:// hoặc https://)."
            return
        }
        isSendingHTTP = true
        let start = Date()
        defer { isSendingHTTP = false }

        var req = URLRequest(url: url)
        req.httpMethod = httpMethod
        req.timeoutInterval = 20
        for line in requestHeadersText.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
            }
        }
        if httpMethod != "GET" && httpMethod != "DELETE" && !requestBodyText.isEmpty {
            req.httpBody = Data(requestBodyText.utf8)
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            responseLatencyMs = Int(Date().timeIntervalSince(start) * 1000)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            responseStatusBadge = "HTTP \(status)"
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let prettyStr = String(data: pretty, encoding: .utf8) {
                responseBody = prettyStr
            } else {
                responseBody = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            }
        } catch {
            responseLatencyMs = Int(Date().timeIntervalSince(start) * 1000)
            responseStatusBadge = "ERROR"
            responseBody = error.localizedDescription
        }
    }

    private func generateCurlCode() -> String {
        var cmd = "curl -X \(httpMethod) \"\(requestURL)\""
        for line in requestHeadersText.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            cmd += " -H \"\(line.trimmingCharacters(in: .whitespaces))\""
        }
        if httpMethod != "GET" && httpMethod != "DELETE" && !requestBodyText.isEmpty {
            cmd += " -d '\(requestBodyText.replacingOccurrences(of: "\n", with: " "))'"
        }
        return cmd
    }

    private func generateJSFetchCode() -> String {
        """
        const res = await fetch("\(requestURL)", {
          method: "\(httpMethod)",
          headers: { "Content-Type": "application/json" }\(httpMethod == "GET" ? "" : ",\n  body: JSON.stringify(\(requestBodyText))")
        });
        console.log(await res.json());
        """
    }

    private func generatePythonRequestsCode() -> String {
        """
        import requests
        r = requests.\(httpMethod.lowercased())("\(requestURL)"\(httpMethod == "GET" ? "" : ", data='''\(requestBodyText)'''"))
        print(r.status_code, r.text)
        """
    }

    // MARK: - 3. Visual .env Secret Editor
    private var envEditorView: some View {
        Form {
            Section {
                HStack {
                    TextField("KEY_NAME", text: $newEnvKey)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("value", text: $newEnvValue)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("+") {
                        let k = newEnvKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        envPairs.append((id: UUID(), key: k, value: newEnvValue, hidden: true))
                        newEnvKey = ""
                        newEnvValue = ""
                        saveEnvPairs()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text(preferences.tr("Thêm biến môi trường (.env)", "Add Variable to .env"))
            }

            Section(preferences.tr("Biến đang có trong .env", "Workspace .env Variables")) {
                if envPairs.isEmpty {
                    Text(preferences.tr("Chưa có biến nào trong .env", "No variables yet in .env"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(envPairs.enumerated()), id: \.element.id) { idx, pair in
                        HStack(spacing: 8) {
                            Text(pair.key)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .frame(minWidth: 90, alignment: .leading)
                            if pair.hidden {
                                SecureField("value", text: Binding(
                                    get: { envPairs[idx].value },
                                    set: { envPairs[idx].value = $0 }
                                ))
                                .font(.system(size: 12, design: .monospaced))
                            } else {
                                TextField("value", text: Binding(
                                    get: { envPairs[idx].value },
                                    set: { envPairs[idx].value = $0 }
                                ))
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }
                            Button {
                                envPairs[idx].hidden.toggle()
                            } label: {
                                Image(systemName: pair.hidden ? "eye" : "eye.slash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                envPairs.remove(at: idx)
                                saveEnvPairs()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    saveEnvPairs()
                } label: {
                    Label(preferences.tr("Lưu file .env ngay (tự đồng bộ PC)", "Save .env Now (Auto-Syncs to PC)"), systemImage: "checkmark.circle.fill")
                }

                if let envSaveNotice {
                    Text(envSaveNotice)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func loadEnvPairs() {
        let envURL = workspace.rootURL.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else {
            envPairs = []
            return
        }
        var loaded: [(id: UUID, key: String, value: String, hidden: Bool)] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            loaded.append((
                id: UUID(),
                key: String(parts[0]).trimmingCharacters(in: .whitespaces),
                value: String(parts[1]).trimmingCharacters(in: .whitespaces),
                hidden: true
            ))
        }
        envPairs = loaded
    }

    private func saveEnvPairs() {
        let text = envPairs.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        workspace.applyAgentFileEdit(relativePath: ".env", newContent: text)
        envSaveNotice = preferences.tr("Đã lưu .env (\(envPairs.count) biến).", "Saved .env (\(envPairs.count) keys).")
    }

    // MARK: - 4. Color Picker & Clipboard Snippet History
    private var colorClipboardView: some View {
        let components = UIColor(pickedColor).cgColor.components ?? [0, 0, 1, 1]
        let r = Int(round((components.count > 0 ? components[0] : 0) * 255))
        let g = Int(round((components.count > 1 ? components[1] : 0) * 255))
        let b = Int(round((components.count > 2 ? components[2] : 0) * 255))
        let hexStr = String(format: "#%02X%02X%02X", r, g, b)
        let rgbStr = "rgb(\(r), \(g), \(b))"
        let swiftUIStr = String(format: "Color(red: %.2f, green: %.2f, blue: %.2f)", Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)

        return Form {
            Section(preferences.tr("Chọn & Chuyển mã Màu CSS / SwiftUI", "CSS & SwiftUI Color Generator")) {
                ColorPicker(preferences.tr("Chọn màu trực quan", "Pick Color"), selection: $pickedColor, supportsOpacity: false)
                colorRow("HEX", hexStr)
                colorRow("CSS", rgbStr)
                colorRow("SwiftUI", swiftUIStr)
            }

            Section(preferences.tr("Lịch sử Snippet / Clipboard nhanh", "Quick Snippet & Clipboard Vault")) {
                HStack {
                    TextField(preferences.tr("Lưu nhanh lệnh hoặc đoạn code...", "Save snippet or note..."), text: $newClipText)
                        .font(.system(size: 12.5, design: .monospaced))
                    Button(preferences.tr("Lưu", "Save")) {
                        let clean = newClipText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        clipNotes.insert(clean, at: 0)
                        newClipText = ""
                        persistClipboardHistory()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                        clipNotes.insert(clip, at: 0)
                        persistClipboardHistory()
                    }
                } label: {
                    Label(preferences.tr("Lưu nội dung hiện có trong Clipboard", "Capture Current Clipboard"), systemImage: "doc.on.clipboard")
                }

                ForEach(Array(clipNotes.enumerated()), id: \.offset) { idx, note in
                    HStack {
                        Text(note)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(2)
                        Spacer()
                        Button(preferences.tr("Copy", "Copy")) {
                            UIPasteboard.general.string = note
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            clipNotes.remove(at: idx)
                            persistClipboardHistory()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func colorRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            Button(preferences.tr("Copy", "Copy")) {
                UIPasteboard.general.string = value
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadClipboardHistory() {
        clipNotes = UserDefaults.standard.stringArray(forKey: "3012.clipVault") ?? []
    }

    private func persistClipboardHistory() {
        if clipNotes.count > 30 {
            clipNotes = Array(clipNotes.prefix(30))
        }
        UserDefaults.standard.set(clipNotes, forKey: "3012.clipVault")
    }
}
