<div align="center">
  <p>
    <img src="Resources/Brand/3012-banner.svg" width="680" alt="3012 — Native Code Editor &amp; Remote Workstation for iOS" />
  </p>
  <p><strong>Native Code Editor, Remote Development Workstation &amp; Agentic IDE for iOS and iPadOS</strong></p>

  <p>
    <a href="https://github.com/userlethekhoi/3012/actions/workflows/build-ipa.yml">
      <img src="https://img.shields.io/github/actions/workflow/status/userlethekhoi/3012/build-ipa.yml?branch=main&style=flat-square&label=CI%20Build" alt="CI Build Status" />
    </a>
    <a href="https://github.com/userlethekhoi/3012/releases/latest">
      <img src="https://img.shields.io/github/v/release/userlethekhoi/3012?style=flat-square&label=Latest%20Release&color=2563eb" alt="Latest Release" />
    </a>
    <a href="https://github.com/userlethekhoi/3012/releases/latest/download/3012-Unsigned.ipa">
      <img src="https://img.shields.io/badge/Download-3012--Unsigned.ipa-10b981?style=flat-square" alt="Download Unsigned IPA" />
    </a>
    <img src="https://img.shields.io/badge/Platform-iOS%2017.0%2B%20%7C%20iPadOS%2017.0%2B-1e293b?style=flat-square" alt="Platform" />
    <img src="https://img.shields.io/badge/Swift-5.10-f05138?style=flat-square" alt="Swift 5.10" />
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/License-GNU%20AGPLv3-0f766e?style=flat-square" alt="GNU AGPLv3 License" />
    </a>
  </p>
</div>

---

## Tổng quan

**3012** (`com.dev.app3012`) là môi trường phát triển tích hợp (IDE) thuần Native dành cho iOS và iPadOS, được thiết kế để mang quy trình làm việc của **VS Code** và **Cursor** lên thiết bị di động mà không đánh đổi hiệu năng thông qua lớp bọc WebView/Electron.

Toàn bộ vùng soạn thảo được xây dựng trực tiếp trên `UIKit` (`Runestone`) kết hợp **48 bộ phân tích cú pháp C/C++ `Tree-sitter` biên dịch tĩnh**, đảm bảo tốc độ cuộn 120Hz ProMotion, độ trễ nhập liệu bằng không, đồng thời tích hợp sẵn máy chủ Web cục bộ (`localhost:5500`), thiết bị đầu cuối `SwiftTerm` VT100/Xterm-256color, kết nối `SSH/SFTP` bảo mật bằng iOS Keychain và trợ lý lập trình tự hành có kiểm duyệt bản vá (`Diff Review`).

---

## Tải xuống & Cài đặt

Mỗi bản cập nhật trên nhánh `main` được hệ thống GitHub Actions biên dịch tự động trên `macos-15` (Xcode 16+) và xuất bản trực tiếp dưới dạng gói ứng dụng chưa ký (**Unsigned `.ipa`**) tại mục **Releases**.

- **Tải trực tiếp bản mới nhất:** [**3012-Unsigned.ipa (Latest Release)**](https://github.com/userlethekhoi/3012/releases/latest/download/3012-Unsigned.ipa)
- **Danh sách toàn bộ các bản phát hành & mã băm SHA-256:** [GitHub Releases](https://github.com/userlethekhoi/3012/releases)

### Hướng dẫn ký chứng chỉ (`.p12` / Sideload)

Vì gói phát hành ở định dạng chuẩn `Unsigned .ipa`, bạn có thể ký bằng chứng chỉ Apple Developer cá nhân (`.p12` + `.mobileprovision`) hoặc công cụ cài đặt tương ứng:

| Công cụ cài đặt | Yêu cầu | Quy trình thực hiện |
| :--- | :--- | :--- |
| **Feather / ESign / GBox** | Chứng chỉ `.p12` + `.mobileprovision` | Nhập chứng chỉ vào ứng dụng ký trên thiết bị, chọn file `3012-Unsigned.ipa`, bấm **Sign & Install**. |
| **AltStore / SideStore** | Apple ID cá nhân (Miễn phí hoặc Trả phí) | Mở file `3012-Unsigned.ipa` qua mục **My Apps (+)** để tự động ký và gia hạn định kỳ. |
| **Sideloadly (macOS / Windows)** | Apple ID hoặc chứng chỉ Developer | Kéo thả `3012-Unsigned.ipa` vào Sideloadly và cài đặt qua cáp USB hoặc Wi-Fi. |
| **TrollStore** | Thiết bị hỗ trợ CoreTrust | Mở trực tiếp `3012-Unsigned.ipa` trong TrollStore để cài đặt vĩnh viễn không cần ký lại. |

---

## Kiến trúc Hệ thống

```mermaid
flowchart TB
    subgraph UI["Presentation & Gesture Layer (SwiftUI + UIKit 120Hz)"]
        Editor["Runestone Code Editor + Pro Coding Bar (Trackpad & Flick Keys)"]
        Explorer["Activity Sidebar (Explorer • Search • Source Control • SSH/SFTP • Open VSX)"]
        Console["Multi-Detent Bottom Panel (SwiftTerm • Output • Problems • Live Preview F12)"]
        AgentUI["Side-by-Side / Drawer Coding Agent + Diff Review"]
    end

    subgraph Intelligence["Language & Formatting Engine"]
        TS["48 Native Tree-sitter AST Parsers (64 Languages)"]
        IntelliSense["Fuzzy / CamelCase / Member Trigger / Emmet / Signature Help"]
        Formatter["CodeFormatterService (Format-on-Save + Remote Industry Formatters)"]
        Diagnostics["Real-time Offline Syntax Linter + Remote Compiler Diagnostics"]
    end

    subgraph Runtime["Local & Remote Execution Infrastructure"]
        LiveSrv["Network.framework HTTP + WebSocket Server (127.0.0.1:5500 + Background Keep-Alive)"]
        ZeroCfg["Zero-Config Cloud Sandbox & JavaScriptCore Engine (30+ Languages)"]
        SSH["Citadel NIOSSH + SFTP Mirroring + DirectTCPIP Local Port Forwarding"]
        Git["Hybrid Git Engine (REST Clone/Push + Local Snapshot & Remote VPS Git)"]
    end

    Editor --> TS
    Editor --> IntelliSense
    Editor --> Formatter
    Editor --> Diagnostics
    Explorer --> Git
    Explorer --> SSH
    Console --> LiveSrv
    Console --> ZeroCfg
    Console --> SSH
```

---

## Tính năng Cốt lõi

### 1. Lõi Soạn thảo 120Hz & Nhận diện Toàn diện 64 Ngôn ngữ
- **48 bộ ngữ pháp `Tree-sitter` C/C++ biên dịch gốc** đi kèm cơ chế nhận diện 3 tầng: đối sánh tên tệp cấu hình đặc biệt (`Dockerfile`, `Makefile`, `CMakeLists.txt`, `Cargo.toml`), hơn **145 phần mở rộng tệp**, và phân tích dòng khai báo đầu tệp (`shebang` / chữ ký cú pháp) cho tệp không có đuôi mở rộng.
- Hỗ trợ đầy đủ các họ ngôn ngữ:
  - **Systems & Native:** C, C++, Objective-C, Rust, Go, Zig, D, Nim, Crystal, Assembly.
  - **Web & Frontend:** HTML, CSS, SCSS, JavaScript, TypeScript, TSX/JSX, Vue, Svelte, Astro, GraphQL.
  - **Mobile, JVM & .NET:** Swift, Dart, Java, Kotlin, Scala, Groovy, C#.
  - **Scripting, Data & Functional:** Python, PHP, Ruby, Perl, Lua, R, Julia, Elixir, Erlang, Haskell, OCaml, Elm, Lisp, Pascal, Solidity.
  - **Database, Config & Infrastructure:** SQL, JSON, JSON5, YAML, TOML, XML, Protocol Buffers, INI/Env, Bash/Zsh, Fish, PowerShell, Dockerfile, Makefile, CMake, Terraform/HCL, Bicep, Nix, Markdown, LaTeX, Regex, Diff.
- **Pro Coding Accessory Bar:** Tích hợp chế độ giữ-vuốt **Trackpad** di chuyển con trỏ chính xác từng ký tự kèm phản hồi xúc giác (Haptics), thao tác vuốt lên (**Flick Keys**) để nhập nhanh cặp ngoặc/toán tử, và cử chỉ thu phóng cỡ chữ (**Pinch-to-Zoom**).

### 2. Smart IntelliSense, Tự động Format theo Ngôn ngữ & Báo lỗi Trực tiếp
- **VS Code-Grade IntelliSense (`CodeIntelligenceService`):**
  - Chấm điểm **Fuzzy Subsequence** và viết tắt **CamelCase / `snake_case`** (ví dụ: gõ `gEBI` khớp `getElementById`, gõ `umap` khớp `std::unordered_map`).
  - Kích hoạt gợi ý tức thì (0 ký tự) ngay sau toán tử truy cập thành phần `.`, `->`, `::` và chỉ thị `#include <`.
  - Bộ mở rộng **Emmet** nội bộ cho HTML/JSX/Vue/Svelte (`!`, `div.card`, `button#submit`, `ul>li*3`), đặt con trỏ tự động vào đúng vị trí thao tác (`$0`), lập chỉ mục hàm xuyên toàn bộ dự án và hiển thị khung nhắc chữ ký tham số hàm (**Signature Help**) ngay khi mở ngoặc.
  - Tự động thụt lề khối lệnh thông minh khi nhấn `Return` giữa `{|}`, `(|)`, `[|]` hoặc sau dấu `:`.
- **Tự động Format Code (`CodeFormatterService`):**
  - Hỗ trợ **Format-on-Save / Format-on-Run** và tổ hợp phím `Cmd + Shift + F`.
  - Kết hợp trình định dạng công nghiệp trên VPS qua SSH (`clang-format`, `gofmt`, `rustfmt`, `zig fmt`, `black`, `prettier`, `dart format`, `swift-format`, `shfmt`, `terraform fmt`, `nixfmt`) với bộ định dạng nội bộ ngoại tuyến bảo toàn chuỗi/chú thích cho cả 64 ngôn ngữ (bao gồm bảo toàn ký tự `\t` bắt buộc cho `Makefile` và `Go`).
- **Chẩn đoán Lỗi Trực tiếp (`Inline Diagnostics`):** Tô sáng trực tiếp dòng lỗi/cảnh báo ngay trên trình soạn thảo kết hợp bảng **Problems** cho phép nhảy tới dòng lỗi hoặc chuyển ngữ cảnh sang Coding Agent để đề xuất bản vá.

### 3. Hệ thống Màu sắc Trạng thái File Chuẩn VS Code (`Working-Tree Decorations`)
Cây thư mục **Explorer**, thanh **Tab đang mở**, và bảng **Source Control** đồng bộ trạng thái thay đổi theo thời gian thực dựa trên mốc cơ sở của dự án:

| Nhãn | Trạng thái | Màu hiển thị | Ý nghĩa kỹ thuật |
| :---: | :--- | :--- | :--- |
| **`U`** | Untracked | Xanh lá (`#73C991`) | Tệp mới được khởi tạo trong không gian làm việc. |
| **`A`** | Added Code | Xanh lá (`#73C991`) | Tệp hiện có được bổ sung thêm dòng lệnh hoặc khối mã nguồn mới. |
| **`M`** | Modified | Vàng hổ phách (`#E2C08D`) | Tệp được chỉnh sửa tại chỗ (thay đổi giá trị/logic) không bổ sung thêm dòng mới. |
| **`D`** | Deleted | Đỏ (`#F14C4C` + gạch ngang) | Tệp vừa bị xóa — vẫn hiển thị trực quan tại vị trí gốc kèm nút **Khôi phục 1 chạm**. |

Các thư mục cha tự động tổng hợp trạng thái của tệp bên trong và hiển thị chấm màu chỉ báo ở cạnh phải tương tự VS Code.

### 4. Built-in Live Server (`127.0.0.1:5500`) & Mobile Web DevTools
- Máy chủ HTTP + WebSocket viết trực tiếp bằng `Network.framework` (`NWListener`), tự động tiêm kênh tín hiệu **Hot-Reload** để làm mới trang tức thì mỗi khi lưu tệp `.html`, `.css`, `.js`.
- **Background Keep-Alive:** Duy trì tiến trình máy chủ `localhost:5500` và đường hầm cổng SSH không bị hệ điều hành iOS đóng băng khi chuyển sang kiểm thử giao diện trên **Safari** hoặc **Chrome**.
- **In-App Web DevTools (`F12`):** Thu thập trực tiếp luồng `console.log`, `console.warn`, `console.error`, ngoại lệ `window.onerror`, cho phép thực thi biểu thức JavaScript trực tiếp và chuyển đổi khung nhìn chuẩn thiết bị (`390px`, `768px`, `1280px`).

### 5. Thực thi Zero-Config & Phát triển Từ xa qua SSH / SFTP (`Citadel` + `SwiftTerm`)
- **Zero-Config 1-Tap Run:** Thực thi trực tiếp hơn **30 ngôn ngữ biên dịch và thông dịch** (C, C++20, Rust, Go, Java, C#, Python, Swift, Zig, PHP, Ruby, Lua, SQL, Haskell, Elixir...) ngay trên điện thoại không cần cấu hình trình biên dịch thủ công.
- **Remote SSH & SFTP Workstation:**
  - Quản lý hồ sơ máy chủ Linux, lưu trữ mật khẩu/khóa bảo mật trong **iOS Keychain**, hỗ trợ sinh cặp khóa **Ed25519** một chạm.
  - Duyệt cây thư mục SFTP từ xa, chỉnh sửa tệp ở tốc độ 120Hz cục bộ và tự động đồng bộ ngược lên VPS khi lưu.
  - Thiết bị đầu cuối tương tác **`SwiftTerm` (`xterm-256color`)** hỗ trợ đầy đủ `vim`, `tmux`, `htop`, `git`, `gdb` và **SSH Local Port Forwarding (`localhost:<port>` ⇄ `VPS:<port>`)**.

### 6. Agentic Coding Assistant (Online + Offline) & Hệ sinh thái Theme / Open VSX
- **Kết nối AI tổng quát, do người dùng tự cấu hình:** Không mặc định cứng nhà cung cấp hay model. Người dùng tự thêm không giới hạn cấu hình (OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, xAI Grok, Mistral, Groq, Together, Fireworks, Moonshot Kimi, Qwen, Z.ai GLM hoặc bất kỳ endpoint OpenAI-compatible nào như vLLM / LiteLLM / proxy trên VPS), chuyển đổi 1 chạm ngay trên đầu khung Agent. API Key lưu trong **iOS Keychain**.
- **Tự động dùng model mới nhất:** Danh sách model được tải trực tiếp từ API `/models` của chính nhà cung cấp (làm mới mỗi 6 giờ hoặc khi bấm kiểm tra). Ở chế độ **Mới nhất** / **Mới nhất (nhanh)**, khi nhà cung cấp phát hành model mới, 3012 tự chuyển sang ngay mà không cần cập nhật app; chế độ **Cố định** cho phép ghim đúng model mong muốn.
- **Phản hồi realtime:** Câu trả lời được stream từng phần (Server-Sent Events) cho mọi định dạng API, có nút dừng tạo phản hồi.
- **Chạy offline:** **Apple On-Device** (Foundation Models, iOS 26+ trên thiết bị hỗ trợ Apple Intelligence) xử lý hoàn toàn trên iPhone; **Ollama / LM Studio** chạy trên máy tính hoặc server trong cùng mạng Wi-Fi mà không cần Internet.
- **Agent hiểu project:** Đọc ngữ cảnh toàn dự án, phân tích đầu ra lỗi biên dịch và đề xuất thay đổi qua giao diện kiểm duyệt **Diff Preview (`Accept & Save` / `Reject`)**.
- **Theme Studio & Open VSX (`.vsix`):** Đi kèm 14 bảng màu chuẩn (*Tokyo Night*, *Cursor Midnight*, *One Dark Pro*, *Dracula*, *Catppuccin*, *Xcode*, *GitHub*...), công cụ **Theme Studio** tùy biến từng mã màu cú pháp, và trình tải trực tiếp gói `.vsix` từ chợ **Open VSX** để cài đặt Color Themes & Snippets.

---

## Quyền riêng tư

- **Không thu thập dữ liệu:** 3012 không tích hợp công cụ theo dõi, phân tích hay quảng cáo và không vận hành máy chủ trung gian.
- **Thông tin xác thực:** API Key, mật khẩu VPS, khóa SSH và GitHub Token chỉ được lưu trong iOS Keychain trên thiết bị.
- **Dữ liệu gửi đi:** Khi sử dụng Coding Agent với nhà cung cấp online, nội dung yêu cầu và ngữ cảnh code liên quan được gửi trực tiếp từ thiết bị tới nhà cung cấp do người dùng chọn, theo chính sách của nhà cung cấp đó. Cấu hình Offline (Apple On-Device, Ollama / LM Studio trong mạng LAN) không gửi dữ liệu ra Internet.

---

## Phím tắt Bàn phím Cứng (Magic Keyboard / Bluetooth)

| Tổ hợp phím | Chức năng |
| :--- | :--- |
| `Cmd + S` | Lưu tệp hiện tại, tự động Format (nếu bật) và ghi mốc lịch sử phiên bản |
| `Cmd + Shift + F` | Định dạng mã nguồn (Format Document) theo ngôn ngữ của tệp đang mở |
| `Cmd + R` | Thực thi thông minh tệp hiện tại (Live Server / Zero-Config Sandbox / SSH VPS) |
| `Cmd + P` | Mở bảng điều khiển lệnh & tìm mở nhanh tệp (`Command Palette & Quick Open`) |
| `Cmd + /` | Bật hoặc tắt chú thích dòng (`Toggle Line Comment`) theo ngôn ngữ |
| `Cmd + B` | Đóng hoặc mở thanh công cụ bên trái (`Activity Sidebar`) |
| `Cmd + I` | Đóng hoặc mở khung trợ lý lập trình (`Coding Agent Panel`) |
| `Cmd + J` | Đóng hoặc mở ngăn kéo dưới (`Terminal / Output / Problems / Live Preview`) |
| `Tab` | Chấp nhận đề xuất đầu tiên trong thanh gợi ý `Smart IntelliSense` |

---

## Tự Biên dịch từ Mã nguồn (Build from Source)

Dự án quản lý cấu hình biên dịch và phụ thuộc Swift Package Manager hoàn toàn thông qua đặc tả khai báo [`project.yml`](project.yml) (**XcodeGen**) nhằm đảm bảo tính tái lập tuyệt đối và tránh xung đột tệp `.xcodeproj`.

### Yêu cầu môi trường
- macOS 15.0+ đi kèm **Xcode 16.0+**
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Các bước biên dịch gói `3012-Unsigned.ipa`

```bash
# 1. Sao chép mã nguồn
git clone https://github.com/userlethekhoi/3012.git
cd 3012

# 2. Sinh tệp dự án Xcode từ project.yml
xcodegen generate

# 3. Tải các gói phụ thuộc Swift Package Manager
xcodebuild -resolvePackageDependencies -project App3012.xcodeproj -scheme App3012

# 4. Biên dịch bản Release cho thiết bị iOS (arm64, không yêu cầu chứng chỉ ký sẵn)
xcodebuild build \
  -project App3012.xcodeproj \
  -scheme App3012 \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

# 5. Đóng gói thành 3012-Unsigned.ipa
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/3012.app Payload/
zip -qry 3012-Unsigned.ipa Payload
```

---

## Cấu trúc Thư mục Dự án

```text
3012/
├── .github/workflows/
│   └── build-ipa.yml               # Pipeline CI/CD biên dịch & phát hành tự động lên GitHub Releases
├── Config/
│   └── Info.plist                  # Khai báo quyền hệ thống, mạng cục bộ và chế độ chạy nền
├── Resources/
│   └── Brand/
│       ├── 3012-banner.svg         # Horizontal vector brand banner cho tài liệu dự án
│       ├── 3012-icon.svg           # Biểu tượng thương hiệu vector gốc (1024-unit grid)
│       └── 3012-icon.png           # Biểu tượng squircle độ phân giải cao
├── Sources/
│   ├── App/
│   │   └── App3012Main.swift       # Điểm khởi chạy ứng dụng & bố cục điều phối trung tâm
│   ├── Resources/
│   │   └── Assets.xcassets/        # Trọn bộ AppIcon chuẩn iOS/iPadOS (@1x/@2x/@3x + 1024px)
│   ├── Models/
│   │   ├── AIProviderModels.swift  # Hồ sơ nhà cung cấp AI, preset online/offline & thuật toán chọn model mới nhất
│   │   ├── AIAgentModels.swift     # Cấu trúc tin nhắn, cấu hình nhà cung cấp AI & bản vá Diff
│   │   ├── EditorThemeModel.swift  # Hệ thống bảng màu cú pháp, trình nhập Theme VS Code & tùy chọn
│   │   └── WorkspaceModels.swift   # Định nghĩa 64 ngôn ngữ, ánh xạ Tree-sitter & trạng thái Diff U/A/M/D
│   ├── Services/
│   │   ├── AIAgentService.swift            # Quản lý hồ sơ AI, tự cập nhật model mới nhất & luồng hội thoại Agent
│   │   ├── AIProviderClient.swift          # Khám phá model & streaming realtime (OpenAI-compatible, Claude, Gemini, Apple On-Device)
│   │   ├── CodeFormatterService.swift      # Bộ định dạng mã nguồn theo ngôn ngữ (Offline + SSH VPS)
│   │   ├── CodeIntelligenceService.swift   # Smart IntelliSense, Fuzzy/CamelCase, Emmet & Inline Diagnostics
│   │   ├── CodeRunnerService.swift         # Bộ định tuyến thực thi Zero-Config cho hơn 30 ngôn ngữ
│   │   ├── ExtensionStoreService.swift     # Tích hợp Open VSX API & giải nén gói .vsix (ZIPFoundation)
│   │   ├── FileTimelineAndArchiveService.swift # Lưu trữ 20 mốc lịch sử tệp cục bộ & nhập/xuất dự án .zip
│   │   ├── GitService.swift                # Quản lý phiên bản cục bộ, GitHub REST Clone/Push & Remote Git
│   │   ├── KeychainVault.swift             # Lưu trữ bảo mật thông tin xác thực & sinh khóa SSH Ed25519
│   │   ├── LiveServerService.swift         # Máy chủ HTTP + WebSocket (:5500) & chế độ Background Keep-Alive
│   │   ├── LocalShellEngine.swift          # Trình giả lập lệnh UNIX thao tác tệp trực tiếp khi ngoại tuyến
│   │   ├── SSHWorkspaceService.swift       # Kết nối Citadel SSH/SFTP, cài đặt Toolchain & Port Forwarding
│   │   └── WorkspaceManager.swift          # Quản lý cây tệp, đa tab, tìm kiếm toàn cục & theo dõi Diff cơ sở
│   └── Views/
│       ├── Components/IDEVectorIcons.swift     # Hệ thống biểu tượng vector thuần khiết & SF Symbols
│       ├── Editor/
│       │   ├── ProCodingAccessoryBar.swift     # Thanh phím tắt lập trình, Trackpad con trỏ & Flick Keys
│       │   └── RunestoneEditorView.swift       # Cầu nối UIKit TextView 120Hz, Auto-Indent & HighlightedRange
│       ├── Panels/
│       │   ├── AIAgentSidePanel.swift          # Khung hội thoại Agent streaming realtime & bảng duyệt Diff
│       │   ├── AIProviderSettingsSheet.swift   # Quản lý nhà cung cấp AI, API Key (Keychain) & danh sách model
│       │   ├── BottomConsolePreviewPanel.swift # Khung Terminal, Output, Problems & Live Preview DevTools
│       │   ├── CommandPaletteSheet.swift       # Bảng điều khiển lệnh nhanh & mở tệp tức thì
│       │   ├── MarkdownMermaidPreviewView.swift# Trình kết xuất tài liệu Markdown & sơ đồ Mermaid trực tiếp
│       │   ├── SwiftTermTerminalView.swift     # Tích hợp thiết bị đầu cuối Xterm-256color & SSH PTY
│       │   └── SymbolAndTimelineSheets.swift   # Danh sách hàm, lịch sử tệp, Theme Studio & chọn ngôn ngữ
│       ├── Settings/SettingsAndThemesSheet.swift # Giao diện tùy chỉnh trình soạn thảo, phông chữ & phím tắt
│       └── Sidebar/LeftExplorerDrawer.swift    # Ngăn kéo 5 phân hệ chuẩn VS Code kèm hiển thị màu U/A/M/D
├── LICENSE                         # Toàn văn giấy phép mã nguồn mở bắt buộc mở nguồn GNU AGPLv3
└── project.yml                     # Đặc tả cấu hình dự án XcodeGen & danh sách phụ thuộc SPM
```

---

## Bản quyền, Quyền Tác giả & Giấy phép Mã nguồn (GNU AGPLv3)

**Copyright (c) 2026 Le The Khoi ([@userlethekhoi](https://github.com/userlethekhoi)).**

Mã nguồn, kiến trúc hệ thống và bộ nhận diện thương hiệu của dự án **3012** được phát hành theo giấy phép [**GNU Affero General Public License v3.0 (AGPL-3.0)**](LICENSE) — giấy phép Copyleft mạnh nhất được công nhận quốc tế nhằm bảo vệ quyền tác giả và đảm bảo tính minh bạch tuyệt đối của mã nguồn.

### Các điều khoản bắt buộc khi Fork, Sử dụng hoặc Phát triển Phái sinh

Bất kỳ cá nhân hay tổ chức nào sao chép, fork, chỉnh sửa, tích hợp một phần hoặc toàn bộ mã nguồn của **3012** đều phải tuân thủ nghiêm ngặt 4 nghĩa vụ pháp lý sau:

1. **Tôn trọng và Giữ nguyên Quyền Tác giả (`Attribution & Copyright Notice`):**
   - Bắt buộc giữ nguyên toàn bộ thông báo bản quyền gốc (`Copyright (c) 2026 Le The Khoi`), tệp [`LICENSE`](LICENSE), và ghi nhận rõ ràng nguồn gốc từ kho lưu trữ chính thức [`github.com/userlethekhoi/3012`](https://github.com/userlethekhoi/3012) trong cả mã nguồn lẫn phần giới thiệu của ứng dụng.
   - Nghiêm cấm mọi hành vi xóa tên tác giả, gỡ bỏ thông tin bản quyền hoặc mạo nhận quyền sở hữu gốc đối với dự án.
2. **Bắt buộc Công khai Toàn bộ Mã nguồn (`Disclose Full Source`):**
   - Nếu bạn **fork, chỉnh sửa, đóng gói lại (`.ipa`, kho ứng dụng)** hoặc **triển khai dưới dạng dịch vụ qua mạng** (theo Điều 13 của AGPL-3.0), bạn **bắt buộc phải công khai toàn bộ mã nguồn hoàn chỉnh** của phiên bản đó — bao gồm tất cả phần mã sửa đổi, tính năng bổ sung và cấu hình biên dịch — để bất kỳ người dùng nào cũng có thể truy cập công khai miễn phí.
3. **Kế thừa Cùng Giấy phép (`Same License — AGPL-3.0`):**
   - Mọi bản fork và sản phẩm phái sinh bắt buộc phải tiếp tục phát hành dưới chính giấy phép **GNU AGPLv3**. Không được phép đóng nguồn (*Closed-Source / Proprietary*) hoặc chuyển đổi sang các giấy phép hạn chế hơn.
4. **Minh bạch Lịch sử Thay đổi (`State Changes`):**
   - Mọi tệp mã nguồn có chỉnh sửa so với bản gốc phải ghi chú rõ ràng nội dung và thời điểm sửa đổi.

| Phạm vi quyền hạn & Nghĩa vụ | Quy định cụ thể theo GNU AGPL-3.0 |
| :--- | :--- |
| **Được phép** | Nghiên cứu, học tập, fork, chỉnh sửa và đóng góp ngược lại (*Pull Request*) cho dự án mở. |
| **Nghĩa vụ bắt buộc** | Giữ nguyên tên tác giả gốc • Đính kèm [`LICENSE`](LICENSE) • **Công khai 100% toàn bộ mã nguồn** của bản fork/bản sửa đổi dưới cùng giấy phép `AGPL-3.0` • Ghi rõ các thay đổi đã thực hiện. |
| **Nghiêm cấm** | Đóng nguồn (*Closed-Source*) sau khi dùng mã nguồn • Xóa thông tin quyền tác giả • Phân phối bản biên dịch `.ipa` hoặc dịch vụ phái sinh mà che giấu mã nguồn thực tế. |

> **Lưu ý về Thương hiệu & Cấp phép Riêng:** Tên gọi **3012** và bộ biểu tượng thương hiệu trong `Resources/Brand/` thuộc quyền sở hữu của tác giả nhằm định danh dự án chính thức; các bản fork độc lập khi phát hành riêng cần ghi rõ là phiên bản phái sinh từ **3012** để tránh gây nhầm lẫn cho người dùng. Mọi nhu cầu sử dụng trong sản phẩm thương mại đóng nguồn nằm ngoài phạm vi `AGPL-3.0` bắt buộc phải có sự đồng ý bằng văn bản từ tác giả [@userlethekhoi](https://github.com/userlethekhoi).
