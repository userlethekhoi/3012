# Kế hoạch & Tiến độ Triển khai — Dự án `3012` (AI-Native Mobile IDE for iOS)

> **Trạng thái hiện tại:** **v3.7.0 Đang kiểm thử CI** — Nâng cấp **Full Workstation Terminal (Lệnh Windows/Linux + AI CLI `claude`/`opencode` + `code <file>` + Compiler `gcc/g++/py/node/swift` + `git` + `zip/unzip` + `wget/curl/ping`)** với toàn quyền đọc/ghi trong Workspace & Files Sandbox.

---

## Tổng kết Toàn bộ 13 Giai Đoạn Triển Khai

### Phase 13 (v3.7.0): Full Workstation Terminal (`claude` / `opencode` / Windows + Linux CLI) (`in_progress`)
- [x] **Terminal AI Coding CLI (`AIAgentService.runTerminalAgentCLI`):** Hỗ trợ gõ trực tiếp `claude "<yêu-cầu>"`, `opencode "<yêu-cầu>"` hoặc vào REPL tương tác (`claude` / `opencode`), tự quét cây file Workspace trong `pwd`, stream phản hồi, tự động ghi file qua `applyAgentFileEdit` và mở ngay lên Editor (`claude auth <key>`, `claude models`, `claude model <id>`).
- [x] **Mở & Quản lý File Toàn Quyền Non-JB (`SwiftTermTerminalContainer`):** Thêm `code <file>` / `open` / `notepad` (mở hoặc tạo mới file lên Editor), `files` / `realpath` (hiện đường dẫn `Files.app` & Sandbox), Tab autocomplete, hỗ trợ nối lệnh `&&` / `;` và xuất file `>` / `>>`.
- [x] **Đầy đủ bộ lệnh Windows CMD/PowerShell + Linux + Dev Tools:** `dir`/`ls`, `cd`/`chdir`, `cls`/`clear`, `tree`, `type`/`cat`, `head`/`tail`/`wc`, `stat`/`attrib`, `mkdir`/`md`, `rmdir`/`rd`, `touch`, `copy`/`cp`/`xcopy`, `move`/`mv`/`ren`, `del`/`rm`, `findstr`/`grep`, `find`/`where`/`which`, `gcc`/`g++`/`clang`/`swift`/`python`/`node`/`npm`/`run`, `git` (`status`, `init`, `add`, `commit`, `log`, `diff`, `branch`, `clone`), `zip`/`unzip`, `wget`/`curl`, `ping`, `ipconfig`, `systeminfo`, `set`/`env`, `tasklist`/`taskkill`.
- [ ] Bump version `3.7.0` (Build 12) & kiểm chứng GitHub Actions `Build 3012 Unsigned IPA` xanh 100%.

### Phase 12 (v3.6.0): Chạy Ngầm Terminal & Treo Bot 24/7 Trên Chính Thiết Bị (`completed` ✅)
- [x] `LocalDaemonService`: Engine chạy script Node.js/JS & Python Bot Adapter 100% nội bộ trên iPhone/iPad (không phụ thuộc VPS chung), tích hợp Keep-Alive chống iOS đóng băng khi tắt màn hình (Silent `AVAudioSession` playback + `UIApplication.beginBackgroundTask` + `NWPathMonitor` + theo dõi Pin).
- [x] `LocalDaemonManagerSheet`: Giao diện bật/tắt 24/7 Background, khởi tạo nhanh Bot Telegram kèm `.env` token, chạy ngầm file đang mở, xem PID & Stream Log trực tiếp.
- [x] Mở rộng `SwiftTermTerminalContainer` & `BottomConsolePreviewPanel`: Hỗ trợ `node`, `python`, `bg`, `bot new`, `ps`, `logs`, `kill`, `keepalive`, `curl` và nút bật nhanh 24/7.
- [x] Tích hợp vào `SettingsAndThemesSheet` & `App3012Main`, bump version `3.6.0` (Build 11) và kiểm chứng GitHub Actions IPA build xanh 100% (Run `#43434575168` -> Release `v3.6.0-b18`, `3012-Unsigned.ipa`).

### Phase 11 (v3.5.1): Thông tin Tác giả & Tùy chỉnh Đa Ngôn Ngữ Giao Diện (`completed` ✅)
- [x] **Hệ thống Đa ngôn ngữ (`AppLocalization.swift`, `EditorThemeModel.swift`):** Hỗ trợ 7 ngôn ngữ (`VI - Tiếng Việt (Mặc định)`, `EN - English`, `ZH - 中文 (简体)`, `JA - 日本語`, `KO - 한국어`, `RU - Русский`, `ES - Español`), lưu vào `UserDefaults` (`3012.appLanguage`) và **mặc định Tiếng Việt** vì nhà phát triển là người Việt Nam, kèm nút chuyển nhanh và đặt lại về Tiếng Việt 1 chạm.
- [x] **Hồ sơ Tác giả (`IDEAuthorInfo`, `SettingsAndThemesSheet.swift`, `App3012Main.swift`, `NOTICE`, `README.md`):** Hiển thị đầy đủ thông tin **Tác giả: Le The Khoi**, **Năm sinh: 2009**, **Telegram: `@coder_009`** (mở trực tiếp `https://t.me/coder_009` & nút sao chép nhanh), cùng liên kết kho mã nguồn mở `GNU AGPLv3` tại Cài đặt, Menu công cụ, Command Palette và màn hình chào mừng.
- [x] **Đồng bộ Đa ngôn ngữ trên các màn hình chính (`SettingsAndThemesSheet.swift`, `App3012Main.swift`, `LeftExplorerDrawer.swift`, `BottomConsolePreviewPanel.swift`, `AIAgentSidePanel.swift`, `TheosBuilderSheet.swift`, `TheosBuildService.swift`, `CommandPaletteSheet.swift`).**
- [x] **Kiểm chứng CI Build Xanh 100% (IPA Run `#43428410469`) & Release `v3.5.1-b15` (`3012-Unsigned.ipa`, 13.25 MB).**

### Phase 10 (v3.5.0): Trình Tạo & Biên Dịch Theos Tweak / Mod Menu (`.deb` / `.dylib`) Ngay Trong `3012` (`completed` ✅)
- [x] **Máy chủ Build Theos Docker Cách Ly (`BuildServer/`):** HTTP build queue `build_server.py` lắng nghe `127.0.0.1:8787` (chỉ mở qua Cloudflare Tunnel, không mở cổng công cộng, không cấp shell), biên dịch từng job trong container `--network none --read-only --cap-drop ALL --user 1000:1000`, giới hạn RAM/CPU/Timeout & chống quá tải, kèm trang trạng thái `GET /` và API `/v1/health`, `/v1/builds`. Kiểm chứng End-to-End Xanh trên `ubuntu-22.04` (Run `#43417271956`).
- [x] **Ngôn ngữ Logos Theos & IntelliSense (`WorkspaceModels.swift`, `CodeIntelligenceService.swift`):** Tự nhận diện `.x`, `.xm`, `.xi`, `.xmi` và file `control` của gói Debian; bổ sung gợi ý `%hook`, `%orig`, `%ctor`, `%dtor`, `%group`, `%init`, `%property`, `%new`, `%c()`, `MSHookFunction`, `MSHookMessageEx` và liệt kê `%hook` trong Symbol Outline.
- [x] **Dịch vụ Build Theos 3 Chế độ & Mẫu Mod Menu 1 Chạm (`TheosBuildService.swift`, `TheosBuilderSheet.swift`):**
  - Tạo 1 chạm bộ khung **Logos Tweak** hoặc **Floating Mod Menu HUD (`MenuOverlayView.h/.mm` + `Tweak.xm`)** kéo thả được kèm công tắc lưu `NSUserDefaults`.
  - Hỗ trợ đầy đủ 3 chuẩn gói **`rootless` / `roothide` / `rootful`** và 3 chế độ build: **Máy chủ Cộng đồng (`https://build.kaydus.xyz`)** có hộp thoại xác nhận quyền riêng tư lần đầu, **VPS SSH Cá nhân**, và **Ngoại tuyến (`.zip` + GitHub Actions)**.
  - Bấm nút **▶ Run (`Cmd+R`)** trong dự án Theos tự động biên dịch và tải `.deb` / `.dylib` về `packages/` để xuất/chia sẻ cài đặt 1 chạm.
- [x] **Kiểm chứng CI Build Xanh 100% (IPA Run `#43417271944` • Build Server Run `#43417271956`) & Release `v3.5.0-b13` (13.18 MB).**

### Phase 9 (v3.4.0): AI Agent Tổng Quát — Tự Cấu Hình, Tự Cập Nhật Model Mới Nhất, Streaming Realtime, Online + Offline (`completed` ✅)
- [x] **Hồ sơ nhà cung cấp AI do người dùng tự cấu hình (`AIProviderModels.swift`, `AIProviderSettingsSheet.swift`):** Bỏ hoàn toàn model mặc định cứng; thêm không giới hạn cấu hình từ 17 preset (OpenAI, Claude, Gemini, DeepSeek, OpenRouter, xAI, Mistral, Groq, Together, Fireworks, Moonshot, Qwen, Z.ai, Custom OpenAI-compatible, Apple On-Device, Ollama, LM Studio), chuyển nhanh ngay trên đầu khung Agent. API Key chuyển từ `UserDefaults` sang **iOS Keychain** (tự động di chuyển cấu hình cũ).
- [x] **Tự động theo dõi model mới nhất (`AIModelRanker`):** Tải danh sách model trực tiếp từ API `/models` của nhà cung cấp (mỗi 6 giờ hoặc bấm kiểm tra), xếp hạng theo ngày phát hành + số thế hệ model, loại bỏ model không phải chat; 3 chế độ **Mới nhất / Mới nhất (nhanh) / Cố định**, bộ lọc model và thông báo khi tự chuyển sang model mới.
- [x] **Streaming realtime (`AIProviderClient.swift`):** SSE cho OpenAI-compatible, Anthropic Messages và Gemini `streamGenerateContent`, nút dừng tạo phản hồi, hiển thị Markdown và thông báo lỗi thân thiện (401/404/429/mất mạng/LAN).
- [x] **Offline:** Apple Foundation Models on-device (iOS 26+, tự kiểm tra khả dụng) và Ollama / LM Studio qua mạng LAN (`NSLocalNetworkUsageDescription`).
- [x] **Kiểm chứng CI Build Xanh 100% (Run `#43410979250`, iOS 26.2 SDK / Xcode 26.3) & Release `v3.4.0-b11` (~13.04 MB); `FoundationModels` được weak-link nên không ảnh hưởng thiết bị iOS 17–25.**

### Phase 8 (v3.3.0): Thiết Kế Thương Hiệu `3012`, Trọn Bộ `AppIcon` Cho `.ipa` & Logo Vector Nội Bộ / GitHub (`completed` ✅)
- [x] **Bộ nhận diện thương hiệu Developer `3012` thuần kỹ thuật (Không Neon Tím, Không Icon AI):** Thiết kế trên lưới kiến trúc `1024×1024` với nền *Anodized Carbon* (`#141A22 -> #0A0D12`), chữ số đơn cách *Titanium Chalk* (`#F1F5F9`) tạo hình riêng (`30` / `12`), dấu gạch chéo bên trong số `0` (*Programmer's Slashed Zero*) và thanh lề trái *Terminal Emerald* (`#10B981`).
- [x] **Đóng gói đầy đủ 18 kích cỡ `AppIcon` vào `.ipa` (`Sources/Resources/Assets.xcassets/AppIcon.appiconset` & `project.yml`):** Bổ sung trọn bộ PNG 24-bit RGB không kênh alpha cho mọi thiết bị iPhone (`20pt`, `29pt`, `40pt`, `60pt @2x/@3x` gồm `180×180`), iPad (`20pt`, `29pt`, `40pt`, `76pt`, `83.5pt @2x`) và `ios-marketing` (`1024×1024`), kèm cờ `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES` và `CFBundleIconName: AppIcon` để hiển thị chuẩn xác trên mọi công cụ ký `.p12` (`Feather`, `ESign`, `GBox`, `AltStore`, `SideStore`, `TrollStore`, `Sideloadly`).
- [x] **Nâng cấp Logo Vector 120Hz bên trong ứng dụng (`IDEVectorIcons.swift`, `App3012Main.swift`, `LeftExplorerDrawer.swift`, `SettingsAndThemesSheet.swift`):** Vẽ trực tiếp biểu tượng `3012` và chữ hiệu ngang `3012_` bằng `SwiftUI Canvas` trên thanh Header góc trái, đỉnh thanh công cụ Sidebar, màn hình chào mừng trình soạn thảo trống và thẻ nhận diện đầu trang Cài đặt.
- [x] **Cập nhật Banner Thương hiệu & Giấy phép Bản quyền `GNU AGPLv3` trên `README.md` (`Resources/Brand/`, `LICENSE`, `NOTICE`):** Bổ sung `3012-banner.svg`, `3012-icon.svg`, `3012-icon.png` khắc phục đường dẫn ảnh trên GitHub, đồng thời thiết lập giấy phép **GNU Affero General Public License v3.0 (`AGPL-3.0`)** bảo vệ quyền tác giả và bắt buộc mọi bản fork / sản phẩm phái sinh phải công khai 100% mã nguồn.
- [x] **Kiểm chứng CI Build Xanh 100% & Xác thực gói `3012-Unsigned.ipa` trên GitHub Releases (`Run #43402981526` -> Release `v3.3.0-b9`).**

### Phase 7 (v3.2.0): Tự Động Xuất Bản GitHub Release `.ipa`, Màu Trạng Thái File VS Code & `README.md` Chuyên Nghiệp (`completed` ✅)
- [x] **Tự động phát hành `3012-Unsigned.ipa` vào GitHub Releases (`.github/workflows/build-ipa.yml`):** Tự động tạo bản Release mới nhất (`--latest`) kèm mã kiểm tra `SHA256SUMS.txt` và đường dẫn tải trực tiếp `releases/latest/download/3012-Unsigned.ipa` ngay sau mỗi lần build xanh.
- [x] **Màu sắc Trạng thái File chuẩn VS Code (`WorkspaceFileDiffStatus` — `U` / `A` / `M` / `D`):** Đồng bộ xuyên suốt trên cây thư mục **Explorer**, thanh **Tab đang mở** và **Source Control**:
  - **Màu Đỏ (`D` + gạch ngang):** File vừa bị xóa vẫn hiển thị trực quan tại thư mục gốc kèm nút **Khôi phục 1 chạm** (`restoreDeletedFile`) hoặc ẩn đi (`dismissDeletedGhost`).
  - **Màu Xanh lá (`U` / `A`):** File mới tạo (`U`) hoặc file hiện có được bổ sung thêm dòng code mới (`A`).
  - **Màu Vàng hổ phách (`M`):** File sửa đổi nội dung tại chỗ mà không bổ sung thêm dòng mới (`M`), kèm chấm màu tổng hợp trạng thái trên các thư mục cha.
- [x] **Tài liệu `README.md` chuẩn Open-Source / Enterprise:** Thiết kế tinh gọn không lạm dụng biểu tượng AI, tích hợp huy hiệu CI/Release tải nhanh, sơ đồ kiến trúc hệ thống, bảng hướng dẫn ký `.p12`, bảng màu trạng thái file và hướng dẫn tự biên dịch từ mã nguồn.

### Phase 6 (v3.1.0): Nhận Diện Toàn Bộ 64 Ngôn Ngữ, Tự Động Format Code & VS Code Smart IntelliSense (`completed` ✅)
- [x] **Universal Programming Language Recognition (64 Ngôn ngữ + 48 `TreeSitter*Runestone` AST):** Nhận diện 3 tầng (tên file đặc biệt `Dockerfile`/`Makefile`/`CMakeLists.txt`/`Cargo.toml` + hơn 145 đuôi mở rộng + quét nội dung/shebang `#!/usr/bin/env ...`), mở rộng thực thi **1-Tap Run cho 30+ ngôn ngữ** (Zero-Config Wandbox + SSH VPS) và thanh chọn **Language Mode (`Auto-Detect` + ghi đè thủ công)** chuẩn VS Code (`WorkspaceModels.swift`, `SymbolAndTimelineSheets.swift`).
- [x] **Automatic Language-Specific Code Formatting (`CodeFormatterService.swift`):** Tự động định dạng code theo từng họ ngôn ngữ ngay khi Lưu/Chạy (`Format on Save`) hoặc bấm 1 chạm `Format` (`Cmd+Shift+F`), kết hợp trình format chuẩn công nghiệp trên VPS (`clang-format`, `gofmt`, `rustfmt`, `zig fmt`, `black`, `prettier`, `dart format`, `swift-format`, `shfmt`, `terraform fmt`, `nixfmt`) và bộ pretty-printer nội bộ an toàn với chuỗi/chú thích cho cả 64 ngôn ngữ (JSON/JSONC, HTML/XML/Vue/Svelte/Astro, SQL, Python/YAML, Makefile giữ `\t`, Go `\t`, C/C++/Rust/Java/TS/Swift/CSS, Ruby/Lua/Elixir/Shell/Pascal/CMake).
- [x] **VS Code-Grade Smart Code Completion & Auto-Indent:** Chấm điểm **Fuzzy Subsequence & CamelCase/snake_case** (`gEBI` -> `getElementById`, `pb` -> `push_back`, `umap` -> `unordered_map`), tự bật gợi ý 0 ký tự ngay sau `.` / `->` / `::` / `#include <`, tích hợp **Emmet HTML/JSX** (`!`, `div.card`, `ul>li*3`), đặt con trỏ tự động vào giữa ngoặc (`$0`), quét ký hiệu xuyên toàn bộ project, hiện khung nhắc tham số hàm (`Signature Help`) và tự động thụt lề khối `{|}` khi nhấn `Enter` (`CodeIntelligenceService.swift`, `RunestoneEditorView.swift`, `App3012Main.swift`).

### Phase 5 (v3.0.0): Gợi Ý Code, Báo Lỗi Trực Tiếp, Theme Studio & Bộ Công Cụ Pro (`completed` ✅)
- [x] **Live Code Autocomplete (Bật/Tắt 1 chạm):** Thanh gợi ý từ khóa, thư viện chuẩn (`std::`, DOM, Python built-ins), ký hiệu trong file và Snippets nổi trực tiếp trên trình soạn thảo + nhấn `Tab` chấp nhận nhanh (`CodeIntelligenceService.swift`).
- [x] **Inline Error & Warning Highlighting (Bật/Tắt 1 chạm):** Tô màu đỏ/cam trực tiếp lên dòng lỗi trên `Runestone` (`HighlightedRange`) kết hợp kiểm tra tức thì offline (`JSONSerialization`, `JavaScriptCore`, HTML tag matcher, Comment/String-aware Bracket & Python/C++ lint) và trình biên dịch thật trên VPS (`g++`/`gcc`/`py_compile`), kèm tab **Problems** nhảy tới dòng lỗi & **Sửa bằng Agent** 1 chạm.
- [x] **14+ Built-in Themes + App Accent + Theme Studio:** Bộ sưu tập 14 theme sáng/tối (*Tokyo Night*, *Cursor Midnight*, *Xcode Dark/Light*, *One Dark Pro*, *Dracula*, *Catppuccin Mocha/Latte*, *Monokai Pro*, *GitHub Dark/Light*, *Nord*, *Gruvbox*, *Solarized*) + dải màu nhấn App Accent + **Theme Studio** chỉnh từng màu cú pháp code & nền ứng dụng có khung xem trước trực tiếp (`SymbolAndTimelineSheets.swift`).
- [x] **Symbol Outline, Breadcrumbs & Code Folding:** Thanh đường dẫn `file > hàm` kèm danh sách nhảy nhanh tới mọi hàm/class/struct/heading và gập/mở khối code trên lề số dòng.
- [x] **In-App Web DevTools (F12 Mobile) trên Live :5500:** Bắt trực tiếp `console.log`/`warn`/`error`/`window.onerror`, chạy thử biểu thức JavaScript trực tiếp (`Eval`) và chuyển khung hình Responsive (`Auto` / `390px` / `768px` / `1280px`).
- [x] **Auto-Save, Local File Timeline (20 mốc khôi phục), Markdown + Mermaid Live Preview, Nhập/Xuất Project `.zip` & Phím tắt Bluetooth/Magic Keyboard (`Cmd+S/R/P///B/I/J`).**

### Phase 1: Core IDE, Pro Coding Bar, Themes & Live Server `:5500` (`completed` ✅)
- [x] `project.yml` (XcodeGen) + `.github/workflows/build-ipa.yml` tự động xuất `3012-Unsigned.ipa`.
- [x] Lõi Editor `Runestone` + 12 bộ ngữ pháp `Tree-sitter` (`HTML`, `CSS`, `JS`, `TS`, `JSON`, `Python`, `C`, `C++`, `Objective-C`, `Swift`, `Markdown`, `Shell`) + Pinch-to-Zoom cỡ chữ.
- [x] `ProCodingAccessoryBar` với `✥ Trackpad` vuốt con trỏ/bôi đen có rung phản hồi + `Flick Keys` vuốt lên gõ ký tự phụ.
- [x] `LiveServerService` chạy `http://127.0.0.1:5500` tự tiêm Hot-Reload + **Silent Audio Background Keep-Alive** giữ server sống ngầm khi mở **Safari**.
- [x] `AIAgentSidePanel` & `AIAgentService` (Gemini, OpenAI, DeepSeek, OpenRouter, Claude, VPS Proxy) đọc hiểu project và đề xuất chỉnh sửa qua bảng **Diff (Accept & Save / Reject)**.

### Phase 2: Terminal `SwiftTerm` Xterm-256color & Quản lý Git / GitHub (`completed` ✅)
- [x] `SwiftTermTerminalContainer` tích hợp `SwiftTerm` VT100/TrueColor kèm dải phím tắt Terminal (`ESC`, `TAB`, `CTRL+C`, `CTRL+D`, `CTRL+L`, mũi tên) + ngăn kéo đáy 3 nấc chiều cao.
- [x] Chế độ kép tự động: **Local UNIX Workspace Shell** khi offline và tự chuyển sang **Interactive SSH PTY (`vim`, `htop`, `tmux`, `bash`)** khi kết nối VPS.
- [x] `GitService` + Tab **Source Control**: Clone trực tiếp bất kỳ repo GitHub nào (`owner/repo`), theo dõi file sửa/thêm/xóa, xem Diff, Commit lịch sử, Push trực tiếp lên GitHub qua PAT hoặc điều khiển `git` trên VPS.

### Phase 3: Remote Development — `Citadel` SSH, SFTP, Keychain & Port Forwarding (`completed` ✅)
- [x] `KeychainVault` lưu mật khẩu VPS, GitHub Token vào **iOS Keychain** + tính năng **Tạo cặp khóa SSH Ed25519 1 chạm** (copy nhanh dòng `ssh-ed25519 ...` dán vào `~/.ssh/authorized_keys`).
- [x] `SSHWorkspaceService` (`Citadel` `0.12.1`): Duyệt cây thư mục **SFTP** trên VPS, bấm mở file sửa mượt 120Hz và **tự động đồng bộ ngược lên VPS mỗi khi lưu**.
- [x] **1-Click VPS Toolchain Installer** (tự động cài `gcc`, `g++`, `clang`, `clangd`, `cmake`, `gdb`, `python3`, `nodejs`, `git`, `ripgrep` trên VPS) + tự động ưu tiên biên dịch trên VPS khi bấm **▶ Run**.
- [x] **SSH Local Port Forwarding (`localhost:<port>` ⇄ `VPS:<port>`)** qua `DirectTCPIP` để xem trực tiếp web/backend đang chạy trên VPS ngay trên **Safari** của iPhone!

### Phase 4: Kho Extension Open VSX (`.vsix`), Code Formatter, Snippets & Remote LSP Check (`completed` ✅)
- [x] `ExtensionStoreService` kết nối trực tiếp API `open-vsx.org` + giải nén gói `.vsix` bằng `ZIPFoundation` để cài đặt 1 chạm **Color Themes** (hỗ trợ cả JSONC có comment) và **Code Snippets** chuẩn VS Code.
- [x] Tích hợp **Command Palette & Quick Open**, **Format Document** (tự gọi `clang-format` / `prettier` / `black` trên VPS hoặc bộ format offline nội bộ) và **Syntax / Remote LSP Diagnostics** (`g++ -fsyntax-only`, `py_compile`, JSON/Bracket validator).

---

## Nhật ký Lỗi & Giải pháp (Errors Log)
| Lỗi / Rủi ro phát hiện sớm | Lần thử | Giải pháp đã áp dụng |
| :--- | :---: | :--- |
| Tên module Swift bắt đầu bằng chữ số (`3012`) | Phòng ngừa | Đặt `PRODUCT_MODULE_NAME: App3012`, giữ `PRODUCT_NAME: "3012"`. |
| `SwiftTerm` `v1.99.x` yêu cầu `swift-tools-version: 6.2` | Phòng ngừa | Ghim dải ổn định `1.11.2 ... 1.13.99` (`swift-tools-version: 5.9`) tương thích hoàn hảo với Xcode 16+. |
| Các kiểu dữ liệu `ByteBuffer`, `PseudoTerminalRequest`, `Curve25519` nằm ở module phụ thuộc bắc cầu của `Citadel` | Phòng ngừa | Khai báo tường minh `NIOCore`, `NIO`, `NIOSSH`, `Crypto` trong `project.yml` để tránh lỗi thiếu module khi biên dịch. |
| Gọi nhầm `extStore.customSnippets` thay vì thuộc tính gộp `extStore.snippets` trong `App3012Main.swift` | 1 | Đổi sang `extStore.snippets` (commit `1e19490`), build xanh 100% ở Run `#43373662958`. |
| `Task { [weak self] in await self?.run() }` suy luận kiểu `Task<()?, Never>` không gán được cho `Task<Void, Never>` | 1 | Khai báo tường minh `() -> Void` + `guard let self` (commit `2c052c9`), build xanh ở Run `#43410979250`. |
| Cách ly Actor Swift Concurrency (`CodeFormatterService.format` gọi `ssh.isConnected` và `Task.detached` gọi `extractSymbols`) | 1 | Đánh dấu `@MainActor` cho `CodeFormatterService.format` và `nonisolated` cho `extractSymbols` + `computeLineUTF16Offsets` (commit `3cee80e`), build xanh 100% ở Run `#43378626235`. |
