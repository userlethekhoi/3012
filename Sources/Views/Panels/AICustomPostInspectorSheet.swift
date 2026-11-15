import SwiftUI
import UIKit

/// Live HTTP Request & Streaming Response Inspector for Custom POST API configs.
/// Features line-numbered Request/Response viewer, live byte/latency metrics pill, history, and export.
public struct AICustomPostInspectorSheet: View {
    public let config: AICustomPostConfig
    public let apiKey: String
    public let model: String
    public let temperature: Double?
    public let maxOutputTokens: Int
    public let autoRunOnAppear: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 1 // 0 = Request, 1 = Response
    @State private var testPrompt: String = "Hey"
    @State private var isRunning: Bool = false
    @State private var runTask: Task<Void, Never>? = nil
    @State private var currentResult: AICustomPostInspectionResult? = nil
    @State private var history: [AICustomPostInspectionResult] = []
    @State private var showExtractedBanner: Bool = false
    @State private var copiedNotice: String? = nil

    public init(
        config: AICustomPostConfig,
        apiKey: String,
        model: String,
        temperature: Double? = nil,
        maxOutputTokens: Int = 2048,
        autoRunOnAppear: Bool = true
    ) {
        self.config = config
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.autoRunOnAppear = autoRunOnAppear
    }

    private var renderedInitialRequestText: String {
        let preview = try? AIProviderClient.buildCustomPostURLRequest(
            config: config,
            apiKey: apiKey,
            model: model,
            system: "You are a helpful coding assistant.",
            history: [AIChatTurn(role: .user, text: testPrompt.isEmpty ? "Hey" : testPrompt)],
            temperature: temperature,
            maxTokens: maxOutputTokens
        ).renderedPreview
        return preview ?? config.bodyTemplate
    }

    private var displayedText: String {
        if selectedTab == 0 {
            return currentResult?.renderedRequestText ?? renderedInitialRequestText
        }
        if let res = currentResult {
            if !res.rawResponseText.isEmpty {
                return res.rawResponseText
            }
            if let err = res.errorMessage, !err.isEmpty {
                return "Error: \(err)"
            }
            return isRunning ? "Đang chờ phản hồi..." : "(Empty response)"
        }
        return "Bấm nút Play (▶) góc trên bên phải để gửi thử POST request."
    }

    private var displayedLines: [String] {
        let raw = displayedText.replacingOccurrences(of: "\r\n", with: "\n")
        return raw.components(separatedBy: "\n")
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                promptStrip
                if let notice = copiedNotice {
                    Text(notice)
                        .font(.caption.bold())
                        .foregroundColor(.green)
                        .padding(.vertical, 3)
                }
                if showExtractedBanner, let extracted = currentResult?.extractedAssistantText, !extracted.isEmpty {
                    extractedPreviewCard(extracted)
                }
                codeViewer
            }

            bottomFloatingControls
        }
        .onAppear {
            if autoRunOnAppear && currentResult == nil && !isRunning {
                startInspection()
            }
        }
        .onDisappear {
            runTask?.cancel()
            runTask = nil
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                runTask?.cancel()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Text("POST")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.10, green: 0.64, blue: 0.28))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))

            Spacer()

            Button {
                if isRunning {
                    runTask?.cancel()
                    runTask = nil
                    isRunning = false
                } else {
                    startInspection()
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isRunning ? .red : .accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var promptStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            TextField("Prompt gửi thử (vd: Hey)", text: $testPrompt)
                .font(.system(size: 12.5, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !model.isEmpty {
                Text(model)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .cornerRadius(5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(9)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func extractedPreviewCard(_ extracted: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Nội dung trích xuất (Assistant Text)", systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
                Button("Copy") {
                    UIPasteboard.general.string = extracted
                    copiedNotice = "Đã copy nội dung trích xuất."
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
            }
            ScrollView {
                Text(extracted)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .cornerRadius(10)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var codeViewer: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(displayedLines.enumerated()), id: \.offset) { idx, lineText in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                            .padding(.vertical, 1)
                            .background(Color(uiColor: .secondarySystemBackground).opacity(0.65))

                        Text(lineText.isEmpty ? " " : lineText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 128)
        }
    }

    private var bottomFloatingControls: some View {
        VStack(spacing: 10) {
            HStack {
                if let res = currentResult {
                    metricsPill(res)
                } else {
                    Text(isRunning ? "Connecting..." : "Ready")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
                }

                Spacer()

                HStack(spacing: 14) {
                    Menu {
                        if history.isEmpty {
                            Text("Chưa có lịch sử")
                        } else {
                            ForEach(history) { item in
                                Button {
                                    currentResult = item
                                } label: {
                                    let code = item.statusCode.map { "\($0)" } ?? "ERR"
                                    Text("\(code) • \(item.formattedDuration) • \(item.formattedBytes)")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    }

                    Button {
                        UIPasteboard.general.string = displayedText
                        copiedNotice = selectedTab == 0 ? "Đã copy Request." : "Đã copy Response."
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    CompatibleTextShareButton(text: { displayedText }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
            }
            .padding(.horizontal, 16)

            // Bottom `Request | Response` switcher pill
            HStack(spacing: 4) {
                switcherPillButton(title: "Request", index: 0)
                switcherPillButton(title: "Response", index: 1)
            }
            .padding(4)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground).opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func metricsPill(_ res: AICustomPostInspectionResult) -> some View {
        let codeStr = res.statusCode.map { "\($0)" } ?? "ERR"
        let isOK = res.statusCode.map { (200..<300).contains($0) } ?? false
        return HStack(spacing: 8) {
            Text(codeStr)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundColor(isOK ? Color(red: 0.10, green: 0.64, blue: 0.28) : .red)

            Divider().frame(height: 12)

            Text(res.formattedDuration)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            Divider().frame(height: 12)

            Text(res.formattedBytes)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            if !res.extractedAssistantText.isEmpty {
                Divider().frame(height: 12)
                Button {
                    showExtractedBanner.toggle()
                } label: {
                    Image(systemName: showExtractedBanner ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private func switcherPillButton(title: String, index: Int) -> some View {
        let selected = (selectedTab == index)
        return Button {
            selectedTab = index
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(selected ? .primary : .secondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color(uiColor: .systemBackground) : Color.clear)
                )
                .shadow(color: selected ? Color.black.opacity(0.08) : .clear, radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func startInspection() {
        runTask?.cancel()
        selectedTab = 1
        copiedNotice = nil
        isRunning = true

        let promptCopy = testPrompt
        let cfgCopy = config
        let keyCopy = apiKey
        let modelCopy = model
        let tempCopy = temperature
        let maxTokCopy = maxOutputTokens

        runTask = Task { @MainActor () -> Void in
            let final = await AIProviderClient.inspectCustomPost(
                config: cfgCopy,
                apiKey: keyCopy,
                model: modelCopy,
                prompt: promptCopy,
                temperature: tempCopy,
                maxOutputTokens: maxTokCopy,
                onLiveUpdate: { partial in
                    self.currentResult = partial
                }
            )
            self.currentResult = final
            self.history.insert(final, at: 0)
            if self.history.count > 10 {
                self.history = Array(self.history.prefix(10))
            }
            self.isRunning = false
        }
    }
}
