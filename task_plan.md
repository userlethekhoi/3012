# Kế hoạch & Tiến độ Triển khai — Dự án `3012` (AI-Native Mobile IDE for iOS)

> **Trạng thái hiện tại:** **v2.0.1 — Pure SVG Vector AppIcon & Native iOS SF Symbols Overhaul** — Loại bỏ 100% icon mặc định trống của iOS và loại bỏ toàn bộ emoji/icon kiểu AI (`sparkles`, `wand.and.stars`, emoji); chuyển hoàn toàn sang **AppIcon Vector/SVG chuẩn Apple HIG** (hỗ trợ Default / Dark / Tinted) và bộ **iOS System SF Symbols + SVG Vector (`IDECodeMarkVector`)**.

---

## Tổng kết Toàn bộ 4 Giai Đoạn Đã Hoàn Thiện

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
