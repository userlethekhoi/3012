import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct SettingsAndThemesSheet: View {
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var daemonService: LocalDaemonService
    var onOpenDaemonManager: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var showJSONImporter: Bool = false
    @State private var showThemeStudio: Bool = false
    @State private var copiedBanner: Bool = false
    @State private var copiedTelegram: Bool = false

    public init(
        preferences: EditorPreferences,
        liveServer: LiveServerService,
        runner: CodeRunnerService,
        daemonService: LocalDaemonService,
        onOpenDaemonManager: @escaping () -> Void = {}
    ) {
        self.preferences = preferences
        self.liveServer = liveServer
        self.runner = runner
        self.daemonService = daemonService
        self.onOpenDaemonManager = onOpenDaemonManager
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - 0. 3012 Developer Brand Identity Header
                Section {
                    HStack(spacing: 14) {
                        IDECodeMarkVector(size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .center, spacing: 10) {
                                Brand3012WordmarkView(height: 19, inkColor: .primary)
                                Text("v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "3.7.1"))
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.16))
                                    .foregroundColor(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255))
                                    .cornerRadius(4)
                            }
                            Text("Native Code Editor & Remote Workstation")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - 1. Interface Language (Default: Tiếng Việt)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AppLanguage.allCases) { lang in
                                let isSelected = (preferences.appLanguage == lang)
                                Button {
                                    preferences.appLanguage = lang
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(lang.shortBadge)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.18))
                                            .foregroundColor(isSelected ? .white : .primary)
                                            .cornerRadius(4)
                                        Text(lang.nativeName)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Picker(
                        preferences.tr(
                            "Ngôn ngữ giao diện",
                            "Interface Language",
                            zh: "界面语言",
                            ja: "表示言語",
                            ko: "인터페이스 언어",
                            ru: "Язык интерфейса",
                            es: "Idioma de la interfaz"
                        ),
                        selection: $preferences.appLanguage
                    ) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.shortBadge) — \(lang.displayName(in: preferences.appLanguage))").tag(lang)
                        }
                    }

                    if preferences.appLanguage != .vietnamese {
                        Button {
                            preferences.appLanguage = .vietnamese
                        } label: {
                            Label(
                                preferences.tr(
                                    "Đặt lại Tiếng Việt (Mặc định)",
                                    "Reset to Tiếng Việt (Default)",
                                    zh: "恢复默认语言 (Tiếng Việt)",
                                    ja: "Tiếng Việt（デフォルト）に戻す",
                                    ko: "Tiếng Việt(기본값)으로 복원",
                                    ru: "Сбросить на Tiếng Việt (По умолчанию)",
                                    es: "Restablecer a Tiếng Việt (Predeterminado)"
                                ),
                                systemImage: "arrow.uturn.backward.circle"
                            )
                            .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text(preferences.tr(
                        "Ngôn Ngữ Giao Diện (Mặc định: Tiếng Việt)",
                        "Interface Language (Default: Vietnamese)",
                        zh: "界面语言（默认：越南语）",
                        ja: "表示言語（デフォルト：ベトナム語）",
                        ko: "인터페이스 언어 (기본값: 베트남어)",
                        ru: "Язык интерфейса (По умолчанию: Вьетнамский)",
                        es: "Idioma de la Interfaz (Predeterminado: Vietnamita)"
                    ))
                }

                // MARK: - 2. Author & Developer Info
                Section {
                    authorInfoRow(
                        label: preferences.tr("Tác giả", "Author", zh: "作者", ja: "作者", ko: "작성자", ru: "Автор", es: "Autor"),
                        value: IDEAuthorInfo.fullName
                    )
                    authorInfoRow(
                        label: preferences.tr("Năm sinh", "Birth Year", zh: "出生年份", ja: "生年", ko: "출생 연도", ru: "Год рождения", es: "Año de nacimiento"),
                        value: String(IDEAuthorInfo.birthYear)
                    )
                    authorInfoRow(
                        label: "Telegram",
                        value: IDEAuthorInfo.telegramHandle,
                        monospaced: true
                    )
                    authorInfoRow(
                        label: preferences.tr("Giấy phép", "License", zh: "许可证", ja: "ライセンス", ko: "라이선스", ru: "Лицензия", es: "Licencia"),
                        value: "\(IDEAuthorInfo.licenseName) (Open Source)"
                    )

                    Button {
                        UIApplication.shared.open(IDEAuthorInfo.telegramURL)
                    } label: {
                        Label(
                            preferences.tr(
                                "Liên hệ qua Telegram (\(IDEAuthorInfo.telegramHandle))",
                                "Contact via Telegram (\(IDEAuthorInfo.telegramHandle))",
                                zh: "通过 Telegram 联系 (\(IDEAuthorInfo.telegramHandle))",
                                ja: "Telegram で連絡 (\(IDEAuthorInfo.telegramHandle))",
                                ko: "Telegram으로 연락 (\(IDEAuthorInfo.telegramHandle))",
                                ru: "Связаться в Telegram (\(IDEAuthorInfo.telegramHandle))",
                                es: "Contactar por Telegram (\(IDEAuthorInfo.telegramHandle))"
                            ),
                            systemImage: "paperplane.fill"
                        )
                        .fontWeight(.semibold)
                    }

                    Button {
                        UIPasteboard.general.string = IDEAuthorInfo.telegramHandle
                        copiedTelegram = true
                    } label: {
                        Label(
                            copiedTelegram
                                ? preferences.tr("Đã sao chép \(IDEAuthorInfo.telegramHandle)!", "Copied \(IDEAuthorInfo.telegramHandle)!", zh: "已复制 \(IDEAuthorInfo.telegramHandle)！", ja: "\(IDEAuthorInfo.telegramHandle) をコピーしました！", ko: "\(IDEAuthorInfo.telegramHandle) 복사됨!", ru: "Скопировано: \(IDEAuthorInfo.telegramHandle)!", es: "¡Copiado \(IDEAuthorInfo.telegramHandle)!")
                                : preferences.tr("Sao chép Telegram (\(IDEAuthorInfo.telegramHandle))", "Copy Telegram Handle (\(IDEAuthorInfo.telegramHandle))", zh: "复制 Telegram (\(IDEAuthorInfo.telegramHandle))", ja: "Telegram ID をコピー (\(IDEAuthorInfo.telegramHandle))", ko: "Telegram 아이디 복사 (\(IDEAuthorInfo.telegramHandle))", ru: "Копировать Telegram (\(IDEAuthorInfo.telegramHandle))", es: "Copiar Telegram (\(IDEAuthorInfo.telegramHandle))"),
                            systemImage: copiedTelegram ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }

                    Button {
                        UIApplication.shared.open(IDEAuthorInfo.githubRepoURL)
                    } label: {
                        Label(
                            preferences.tr(
                                "Mã nguồn GitHub (userlethekhoi/3012)",
                                "GitHub Repository (userlethekhoi/3012)",
                                zh: "GitHub 开源仓库 (userlethekhoi/3012)",
                                ja: "GitHub リポジトリ (userlethekhoi/3012)",
                                ko: "GitHub 저장소 (userlethekhoi/3012)",
                                ru: "Репозиторий GitHub (userlethekhoi/3012)",
                                es: "Repositorio GitHub (userlethekhoi/3012)"
                            ),
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                    }
                } header: {
                    Text(preferences.tr(
                        "Thông Tin Tác Giả & Nhà Phát Triển",
                        "Author & Developer",
                        zh: "作者与开发者信息",
                        ja: "作者・開発者情報",
                        ko: "작성자 및 개발자 정보",
                        ru: "Автор и разработчик",
                        es: "Autor y Desarrollador"
                    ))
                }

                // MARK: - 3. Code Intelligence, Auto-Format & Inline Diagnostics Toggles
                Section {
                    Toggle(preferences.tr("Bật gợi ý code thông minh như VS Code (IntelliSense)", "Enable VS Code Smart IntelliSense", zh: "启用智能代码补全 (IntelliSense)", ja: "スマートコード補完を有効化 (IntelliSense)", ko: "스마트 코드 완성 활성화 (IntelliSense)", ru: "Умное автодополнение (IntelliSense)", es: "Autocompletado inteligente (IntelliSense)"), isOn: $preferences.enableCodeCompletion)
                    Toggle(preferences.tr("Bật tô sáng & báo lỗi trực tiếp (Inline Diagnostics)", "Enable Inline Error Diagnostics", zh: "启用实时内联错误诊断", ja: "インラインエラー診断を有効化", ko: "인라인 오류 진단 활성화", ru: "Встроенная диагностика ошибок", es: "Diagnóstico de errores en línea"), isOn: $preferences.enableLiveDiagnostics)
                    Toggle(preferences.tr("Tự động Format Code theo ngôn ngữ khi Lưu / Chạy", "Auto-Format Code on Save / Run", zh: "保存/运行时自动格式化代码", ja: "保存・実行時に自動フォーマット", ko: "저장/실행 시 자동 코드 포맷", ru: "Автоформатирование при сохранении/запуске", es: "Formateo automático al guardar / ejecutar"), isOn: $preferences.formatOnSave)
                    Toggle(preferences.tr("Tự động thụt lề thông minh khi nhấn Enter", "Smart Auto-Indent on Return", zh: "回车时智能自动缩进", ja: "改行時にスマートインデント", ko: "Enter 시 스마트 자동 들여쓰기", ru: "Умный автоотступ по Enter", es: "Sangría automática inteligente al pulsar Enter"), isOn: $preferences.autoIndentOnReturn)
                    Toggle(preferences.tr("Tự động lưu & ghi lịch sử phiên bản (Auto-Save)", "Auto-Save & Record Version Snapshots", zh: "自动保存并记录版本历史", ja: "自動保存とバージョン履歴を記録", ko: "자동 저장 및 버전 기록", ru: "Автосохранение и история версий", es: "Autoguardado e historial de versiones"), isOn: $preferences.enableAutoSave)
                    Toggle(preferences.tr("Hiện thanh đường dẫn & danh sách hàm (Breadcrumbs)", "Show Breadcrumbs & Symbol Outline", zh: "显示面包屑导航与符号列表", ja: "パンくずリストとシンボル一覧を表示", ko: "경로 탐색 및 심볼 아웃라인 표시", ru: "Показывать навигацию (Breadcrumbs)", es: "Mostrar ruta de navegación (Breadcrumbs)"), isOn: $preferences.showBreadcrumbs)
                    Toggle(preferences.tr("Cho phép gập/mở khối code (Code Folding)", "Enable Code Folding", zh: "允许代码折叠", ja: "コード折りたたみを有効化", ko: "코드 접기 활성화", ru: "Сворачивание блоков кода", es: "Plegado de código"), isOn: $preferences.enableCodeFolding)
                } header: {
                    Text(preferences.tr(
                        "Gợi Ý Code Thông Minh, Format & Báo Lỗi Trực Tiếp",
                        "Smart IntelliSense, Formatting & Diagnostics",
                        zh: "智能代码提示、格式化与错误诊断",
                        ja: "スマート補完・フォーマット・エラー診断",
                        ko: "스마트 자동완성, 포맷 및 오류 진단",
                        ru: "IntelliSense, форматирование и диагностика",
                        es: "IntelliSense, Formato y Diagnóstico"
                    ))
                } footer: {
                    Text(preferences.tr(
                        "Hỗ trợ nhận diện 64 ngôn ngữ lập trình, gợi ý Fuzzy/CamelCase, gợi ý thành phần sau dấu chấm (./::/->), gõ tắt Emmet HTML và tự động căn chỉnh định dạng code chuẩn theo từng ngôn ngữ.",
                        "Supports 64 programming languages, Fuzzy/CamelCase ranking, member triggers (./::/->), Emmet HTML expansion, and language-aware formatting."
                    ))
                }

                // MARK: - 4. Full Syntax Color & App Theme Gallery + Theme Studio
                Section(preferences.tr(
                    "Bộ Sưu Tập Theme Màu Code & Giao Diện App",
                    "Syntax Themes & App Appearance",
                    zh: "代码配色主题与外观",
                    ja: "シンタックステーマ＆外観",
                    ko: "코드 테마 및 앱 외관",
                    ru: "Темы подсветки и интерфейс",
                    es: "Temas de Sintaxis y Apariencia"
                )) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(preferences.allThemes) { theme in
                                themePreviewCard(theme)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Picker(preferences.tr("Chọn nhanh Theme", "Quick Theme Picker", zh: "快速选择主题", ja: "テーマを選択", ko: "빠른 테마 선택", ru: "Выбор темы", es: "Selección rápida de tema"), selection: $preferences.selectedThemeID) {
                        ForEach(preferences.allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }

                    // App Accent Swatch Bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(preferences.tr("Màu nhấn ứng dụng (App Accent)", "App Accent Color", zh: "应用强调色", ja: "アクセントカラー", ko: "앱 강조 색상", ru: "Акцентный цвет", es: "Color de acento"))
                                .font(.subheadline)
                            Spacer()
                            Text(preferences.customAccentHex.isEmpty ? preferences.tr("Theo Theme", "From Theme") : preferences.customAccentHex)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(EditorPreferences.appAccentPresets, id: \.name) { preset in
                                    let isSelected = (preferences.customAccentHex == preset.hex)
                                    Button {
                                        preferences.customAccentHex = preset.hex
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(preset.hex.isEmpty ? Color(hex: preferences.activePalette.accent) : Color(hex: preset.hex))
                                                .frame(width: 14, height: 14)
                                            Text(preset.hex.isEmpty ? preferences.tr("Theo Theme", "From Theme") : preset.name)
                                                .font(.system(size: 11.5, weight: isSelected ? .bold : .regular))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        showThemeStudio = true
                    } label: {
                        Label(preferences.tr("Mở Theme Studio (Tự chỉnh màu Code & Nền App)", "Open Theme Studio (Customize Code & App Colors)", zh: "打开 Theme Studio（自定义配色）", ja: "Theme Studio を開く（カスタム配色）", ko: "Theme Studio 열기 (색상 맞춤 설정)", ru: "Открыть Theme Studio (Настройка цветов)", es: "Abrir Theme Studio (Personalizar colores)"), systemImage: "slider.horizontal.below.square.filled.and.square")
                            .fontWeight(.semibold)
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label(preferences.tr("Import File Theme .json từ VS Code", "Import VS Code Theme .json", zh: "导入 VS Code .json 主题", ja: "VS Code .json テーマを読み込む", ko: "VS Code 테마 .json 가져오기", ru: "Импорт темы .json из VS Code", es: "Importar tema .json de VS Code"), systemImage: "square.and.arrow.down")
                    }
                }

                // MARK: - 5. Font & Editor Layout
                Section(preferences.tr(
                    "Font Chữ & Hiển Thị Vùng Code",
                    "Typography & Editor Layout",
                    zh: "字体与编辑器布局",
                    ja: "フォントとエディタ表示",
                    ko: "글꼴 및 에디터 레이아웃",
                    ru: "Шрифты и отображение редактора",
                    es: "Fuente y Diseño del Editor"
                )) {
                    Picker(preferences.tr("Font chữ", "Font Family", zh: "字体", ja: "フォント", ko: "글꼴", ru: "Шрифт", es: "Fuente"), selection: $preferences.fontName) {
                        ForEach(EditorPreferences.availableFonts, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text(preferences.tr("Cỡ chữ (Hỗ trợ Pinch-to-Zoom)", "Font Size (Pinch-to-Zoom)", zh: "字号（支持双指缩放）", ja: "文字サイズ（ピンチズーム対応）", ko: "글자 크기 (핀치 줌 지원)", ru: "Размер шрифта (Pinch-to-Zoom)", es: "Tamaño de fuente (Pinch-to-Zoom)"))
                            Spacer()
                            Text("\(Int(preferences.fontSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.fontSize, in: 10...28, step: 0.5)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text(preferences.tr("Giãn dòng (Line Height)", "Line Height", zh: "行高", ja: "行の高さ", ko: "줄 간격", ru: "Межстрочный интервал", es: "Altura de línea"))
                            Spacer()
                            Text(String(format: "%.2fx", preferences.lineHeightMultiplier))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.lineHeightMultiplier, in: 1.0...1.65, step: 0.05)
                    }

                    Picker(preferences.tr("Độ rộng phím Tab", "Tab Width", zh: "Tab 宽度", ja: "タブ幅", ko: "탭 너비", ru: "Ширина Tab", es: "Ancho de tabulación"), selection: $preferences.tabWidth) {
                        Text("2 Spaces").tag(2)
                        Text("4 Spaces").tag(4)
                    }

                    Toggle(preferences.tr("Tự xuống dòng (Word Wrap)", "Word Wrap", zh: "自动换行", ja: "行の折り返し", ko: "자동 줄바꿈", ru: "Перенос строк", es: "Ajuste de línea"), isOn: $preferences.wordWrap)
                    Toggle(preferences.tr("Hiện số dòng (Line Numbers)", "Show Line Numbers", zh: "显示行号", ja: "行番号を表示", ko: "줄 번호 표시", ru: "Номера строк", es: "Mostrar números de línea"), isOn: $preferences.showLineNumbers)
                    Toggle(preferences.tr("Hiện ký tự khoảng trắng ẩn", "Show Invisible Characters", zh: "显示不可见字符", ja: "不可視文字を表示", ko: "공백 문자 표시", ru: "Невидимые символы", es: "Caracteres invisibles"), isOn: $preferences.showInvisibleCharacters)
                }

                // MARK: - 6. Live Server & Safari
                Section(preferences.tr("Live Server (:5500) & Xem Trên Safari", "Live Server (:5500) & Safari Preview", zh: "Live Server (:5500) 与 Safari 预览", ja: "Live Server (:5500) と Safari プレビュー", ko: "Live Server (:5500) 및 Safari 미리보기", ru: "Live Server (:5500) и Safari", es: "Live Server (:5500) y Safari")) {
                    Toggle(preferences.tr("Giữ localhost:5500 chạy ngầm khi mở Safari", "Keep localhost:5500 Alive in Background", zh: "切换至 Safari 时在后台保持 localhost:5500 运行", ja: "Safari 使用中も localhost:5500 をバックグラウンド維持", ko: "Safari 사용 중에도 localhost:5500 백그라운드 유지", ru: "Держать localhost:5500 в фоне для Safari", es: "Mantener localhost:5500 en segundo plano"), isOn: $preferences.keepServerInBackground)
                        .onChange(of: preferences.keepServerInBackground) { _, enabled in
                            liveServer.updateBackgroundKeepAlive(enabled: enabled)
                        }

                    Text(preferences.tr(
                        "Khi bật tùy chọn này, bạn có thể viết HTML/CSS/JS trong 3012 rồi chuyển sang Safari mở http://localhost:\(liveServer.port) mà iOS không đóng băng máy chủ.",
                        "When enabled, you can edit HTML/CSS/JS in 3012 and switch to Safari at http://localhost:\(liveServer.port) without iOS suspending the server."
                    ))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                // MARK: - 6b. On-Device 24/7 Background Terminal & Bot Runner
                Section(preferences.tr(
                    "Terminal & Treo Bot Chạy Ngầm 24/7 (Trên Máy)",
                    "On-Device 24/7 Background Terminal & Bot Runner",
                    zh: "本机 24/7 后台终端与机器人运行",
                    ja: "端末内 24/7 バックグラウンド・Bot 実行",
                    ko: "기기 내 24/7 백그라운드 터미널 & 봇 실행",
                    ru: "Локальный 24/7 фон для терминала и ботов",
                    es: "Terminal y Bots 24/7 en Segundo Plano (Local)"
                )) {
                    Toggle(
                        preferences.tr(
                            "Giữ Terminal & Bot chạy ngầm 24/7 khi tắt màn hình (Chạy trên máy)",
                            "Keep Terminal & Bots Alive 24/7 When Screen Off (On-Device)"
                        ),
                        isOn: $daemonService.keepTerminalAliveInBackground
                    )

                    Toggle(
                        preferences.tr(
                            "Tự khởi động lại Bot nếu gặp lỗi / rớt mạng",
                            "Auto-Restart Bot on Error / Network Drop"
                        ),
                        isOn: $daemonService.autoRestartOnError
                    )

                    Toggle(
                        preferences.tr(
                            "Chống tự tắt màn hình khi đang mở 3012",
                            "Prevent Screen Auto-Lock While 3012 is Open"
                        ),
                        isOn: $daemonService.preventScreenSleep
                    )

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onOpenDaemonManager()
                        }
                    } label: {
                        HStack {
                            Label(
                                preferences.tr("Quản lý Bot Telegram & Tiến trình Ngầm", "Manage Telegram Bots & Background Jobs"),
                                systemImage: "cpu.fill"
                            )
                            Spacer()
                            Text("\(daemonService.runningJobsCount)")
                                .font(.caption.monospacedDigit().bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(daemonService.runningJobsCount > 0 ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                                .foregroundColor(daemonService.runningJobsCount > 0 ? .green : .secondary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(preferences.tr(
                        "Chạy hoàn toàn trên iPhone/iPad của bạn (không tải lên VPS chung), giữ kết nối mạng & tiến trình bot Telegram sống kể cả khi khóa màn hình miễn là còn pin & mạng.",
                        "Runs 100% locally on your iPhone/iPad (not on any shared VPS), keeping Telegram bot pollers and scripts alive even with the screen locked as long as battery and network remain."
                    ))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                // MARK: - 7. Zero-Config Compiler & VPS
                Section(preferences.tr("Zero-Config Compiler & Kết nối VPS Riêng", "Zero-Config Compiler & Private VPS Runner", zh: "零配置编译器与私有 VPS 连接", ja: "ゼロ設定コンパイラと VPS 接続", ko: "제로 설정 컴파일러 및 개인 VPS 연결", ru: "Компилятор Zero-Config и свой VPS", es: "Compilador Zero-Config y VPS Privado")) {
                    TextField(preferences.tr("URL Runner trên VPS (Tùy chọn)", "VPS Runner URL (Optional)", zh: "VPS Runner 地址（可选）", ja: "VPS Runner URL（任意）", ko: "VPS Runner URL (선택)", ru: "URL раннера на VPS (необязательно)", es: "URL del Runner en VPS (Opcional)"), text: $runner.vpsEndpointURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField(preferences.tr("VPS Bearer Token (Tùy chọn)", "VPS Bearer Token (Optional)"), text: $runner.vpsAuthToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        UIPasteboard.general.string = CodeRunnerService.vpsBootstrapCommand
                        copiedBanner = true
                    } label: {
                        Label(
                            copiedBanner
                                ? preferences.tr("Đã copy lệnh cài Toolchain VPS!", "Copied VPS Toolchain Setup Command!")
                                : preferences.tr("Copy lệnh 1-Click cài C++/Python/Node cho VPS", "Copy 1-Click C++/Python/Node VPS Setup Command"),
                            systemImage: copiedBanner ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }

                    Text(preferences.tr(
                        "Mặc định nếu để trống VPS, 3012 vẫn tự biên dịch & chạy ngay C, C++20, Objective-C, Python, Swift, JS bằng Zero-Config Sandbox mà không cần cài MinGW hay sửa PATH.",
                        "Without a VPS configured, 3012 compiles and runs C, C++20, Objective-C, Python, Swift, and JS immediately via Zero-Config Sandbox."
                    ))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                // MARK: - 8. Hardware Keyboard Shortcuts Reference
                Section(preferences.tr("Phím Tắt Bàn Phím Bluetooth / Magic Keyboard", "Hardware Keyboard Shortcuts", zh: "外接键盘快捷键", ja: "ハードウェアキーボードショートカット", ko: "외장 키보드 단축키", ru: "Сочетания клавиш (Magic Keyboard)", es: "Atajos de Teclado Físico")) {
                    shortcutRow("Cmd + S", preferences.tr("Lưu file & tự động Format (nếu bật)", "Save & Auto-Format (if enabled)"))
                    shortcutRow("Cmd + Shift + F", preferences.tr("Format Code theo ngôn ngữ hiện tại", "Format Document by Language"))
                    shortcutRow("Cmd + R", preferences.tr("Chạy file hiện tại (Smart Run 30+ ngôn ngữ)", "Smart Run Active File (30+ Languages)"))
                    shortcutRow("Cmd + P", preferences.tr("Mở Command Palette & tìm nhanh file", "Open Command Palette & Quick Open"))
                    shortcutRow("Cmd + /", preferences.tr("Bật/tắt chú thích dòng (Toggle Comment)", "Toggle Line Comment"))
                    shortcutRow("Cmd + B", preferences.tr("Đóng/mở thanh Explorer bên trái", "Toggle Left Explorer Sidebar"))
                    shortcutRow("Cmd + I", preferences.tr("Đóng/mở khung Coding Agent", "Toggle Coding Agent Panel"))
                    shortcutRow("Cmd + J", preferences.tr("Đóng/mở bảng Terminal / Problems / Web F12", "Toggle Terminal / Problems / Web F12"))
                }
            }
            .navigationTitle(preferences.tr(
                "Cài đặt 3012 IDE",
                "3012 IDE Settings",
                zh: "3012 IDE 设置",
                ja: "3012 IDE 設定",
                ko: "3012 IDE 설정",
                ru: "Настройки 3012 IDE",
                es: "Ajustes de 3012 IDE"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done", zh: "关闭", ja: "閉じる", ko: "닫기", ru: "Готово", es: "Cerrar")) { dismiss() }
                }
            }
            .sheet(isPresented: $showThemeStudio) {
                ThemeStudioEditorSheet(preferences: preferences)
            }
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let imported = VSCodeThemeImporter.parse(jsonData: data, fallbackName: url.deletingPathExtension().lastPathComponent) {
                        preferences.upsertCustomTheme(imported)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func authorInfoRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(size: 13.5, weight: .semibold, design: .monospaced) : .system(size: 13.5, weight: .semibold))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func themePreviewCard(_ theme: IDEColorPalette) -> some View {
        let isSelected = (preferences.selectedThemeID == theme.id)
        Button {
            preferences.selectedThemeID = theme.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: theme.keyword)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.function)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.string)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.number)).frame(width: 8, height: 8)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: theme.accent))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("fn ")
                            .foregroundColor(Color(hex: theme.keyword))
                        Text("main")
                            .foregroundColor(Color(hex: theme.function))
                        Text("()")
                            .foregroundColor(Color(hex: theme.foreground))
                    }
                    Text("\"3012 IDE\"")
                        .foregroundColor(Color(hex: theme.string))
                }
                .font(.system(size: 10.5, design: .monospaced))

                Text(theme.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: theme.foreground))
                    .lineLimit(1)
            }
            .padding(9)
            .frame(width: 132, alignment: .leading)
            .background(Color(hex: theme.editorBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(hex: theme.accent) : Color.secondary.opacity(0.28), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(desc)
                .font(.system(size: 13))
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(5)
        }
    }
}
