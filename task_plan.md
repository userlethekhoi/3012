# Kế hoạch & Tiến độ Triển khai — Dự án `3012` (AI-Native Mobile IDE for iOS)

> **Trạng thái hiện tại:** **v3.1.0 (Build 5) — Đang chạy xác minh CI trên GitHub Actions** — Nâng cấp nhận diện toàn diện **64 ngôn ngữ lập trình** (48 bộ ngữ pháp `Tree-sitter` native + 3 tầng nhận diện), **Tự động Format Code theo ngôn ngữ** (`CodeFormatterService` + Format-on-Save/Run), và **VS Code Smart IntelliSense** (Fuzzy/CamelCase, gợi ý sau dấu `.` / `->` / `::` / `#include <`, Emmet HTML, đặt con trỏ thông minh `$0`, gợi ý tham số hàm trực tiếp & Auto-Indent khi nhấn Enter).

---

## Tổng kết Toàn bộ 6 Giai Đoạn Triển Khai

### Phase 6 (v3.1.0): Nhận Diện Toàn Bộ 64 Ngôn Ngữ, Tự Động Format Code & VS Code Smart IntelliSense (`in_progress`)
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
