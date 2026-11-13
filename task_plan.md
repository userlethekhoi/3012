# Kế hoạch & Tiến độ Triển khai — Dự án `3012` (AI-Native Mobile IDE for iOS)

> **Trạng thái hiện tại:** **Phase 1 ĐÃ HOÀN TẤT MÃ NGUỒN (`completed`)** — Sẵn sàng `git push` lên GitHub để GitHub Actions tự động xuất file **`3012-Unsigned.ipa`**.
> **Tài liệu thiết kế gốc:** `BLUEPRINT.md` (v2.0) & `AGENTS.md`.

---

## 1. Thông tin Cốt lõi Đã Chốt
- **Tên App:** `3012` (`Bundle ID`: `com.dev.app3012`, tự ký ngoài bằng chứng chỉ `.p12` riêng)
- **Môi trường Build:** Windows (`C:\3012`) $\rightarrow$ GitHub Actions (`macos-15` + Xcode 16+ + `XcodeGen`) $\rightarrow$ Artifact **`3012-Unsigned.ipa`**
- **4 Trụ cột Đã Tích Hợp Ngay Từ Bản Đầu:**
  1. **Zen-First 90% Code + Pro Coding Bar:** Vuốt mép trái mở Explorer, vuốt mép phải mở AI Agent, thanh phím lập trình kèm **Trackpad vuốt di chuyển con trỏ** & **Flick Keys**, Pinch-to-Zoom cỡ chữ.
  2. **Built-in Live Server (`http://127.0.0.1:5500`) + Xem ngoài Safari:** Tự động Hot-Reload khi sửa HTML/CSS/JS + chế độ **Background Keep-Alive** giữ `localhost:5500` sống ngầm khi chuyển sang Safari/Chrome.
  3. **Zero-Config 1-Tap Runner:** Bấm **▶ Run** chạy ngay `C`, `C++20`, `Objective-C`, `Python 3.12`, `Swift`, `JavaScript`, `TypeScript`, `Shell` mà **không cần cài MinGW hay cấu hình PATH**; kèm tuỳ chọn nối **VPS riêng** (có sẵn lệnh 1-Click cài full compiler cho VPS).
  4. **AI Coding Agent Cạnh Cửa Sổ Code:** Phong cách Antigravity / Cursor / Copilot hỗ trợ Gemini, OpenAI, DeepSeek, OpenRouter, Claude & VPS Proxy; tự đọc project và xuất bảng **Diff (Accept & Save / Reject)** ngay trong khung chat.

---

## 2. Trạng Thái Các Giai Đoạn (Phases)

### Phase 1: Core IDE, Live Server (:5500 & Safari), Zero-Config Runner & AI Agent (`completed` ✅)
- [x] `project.yml` (XcodeGen) + `.github/workflows/build-ipa.yml` tự động xuất `3012-Unsigned.ipa`.
- [x] `Sources/Models/WorkspaceModels.swift` — Hỗ trợ 12+ ngôn ngữ (`HTML`, `CSS`, `JS`, `TS`, `JSON`, `Python`, `C`, `C++`, `Objective-C`, `Swift`, `Markdown`, `Shell`) qua `TreeSitterLanguages` + starter templates.
- [x] `Sources/Models/EditorThemeModel.swift` — 5 Theme cài sẵn (*Tokyo Night, One Dark Pro, Dracula, Catppuccin Mocha, GitHub Light*) + **Bộ đọc file `.json` Theme của VS Code** + tuỳ chỉnh Font & Pinch-to-Zoom.
- [x] `Sources/Services/WorkspaceManager.swift` — Quản lý cây thư mục đầy đủ (Tạo file/folder, đổi tên, xóa, mở đa tab, tìm kiếm toàn project, mở thư mục ngoài iOS Files).
- [x] `Sources/Services/LiveServerService.swift` — HTTP Server `localhost:5500` (`NWListener`) tự tiêm script Hot-Reload + **Silent Audio Background Keep-Alive** để xem trực tiếp trên **Safari** không bị tắt ngầm.
- [x] `Sources/Services/CodeRunnerService.swift` — Zero-Config 1-Tap Run (`JavaScriptCore` nội bộ + Zero-Config C/C++/Python/Swift Sandbox + cầu nối VPS riêng + Local Shell cơ bản).
- [x] `Sources/Services/AIAgentService.swift` — AI Coding Agent đọc toàn bộ ngữ cảnh project & tạo/sửa file qua thẻ `<file_edit>` kèm xem trước Diff.
- [x] `Sources/Views/` & `Sources/App/App3012Main.swift` — Giao diện Zen-First 90% code, `ProCodingAccessoryBar` (Trackpad + Flick Keys), `AIAgentSidePanel` (Side-by-side / Right Swipe), `BottomConsolePreviewPanel` & `LeftExplorerDrawer`.

### Phase 2: Nâng cấp Terminal `SwiftTerm` VT100 & Git Client Trực quan (`pending`)
- [ ] Tích hợp `SwiftTerm` đầy đủ chuẩn Xterm 256-color / TrueColor.
- [ ] Bổ sung Git Client trực quan (`clone`, `status`, `diff`, `commit`, `push`, `pull`).

### Phase 3: Remote Development — `Citadel` SSH, SFTP & Port Forwarding (`pending`)
- [ ] Tích hợp `Citadel` quản lý danh sách VPS + khóa SSH Keychain (Face ID).
- [ ] Gắn trực tiếp cây thư mục SFTP của VPS vào `WorkspaceManager` + Terminal SSH PTY thật chạy `vim`, `htop`, `tmux`, `g++`, `docker` + tự động SSH Port Forwarding sang Safari.

### Phase 4: Kho Extension Open VSX Trực tiếp & Cầu nối Remote LSP (`pending`)
- [ ] Trình duyệt tìm và cài đặt 1 chạm gói `.vsix` (Themes / Icons / Snippets) trực tiếp từ API `open-vsx.org` ngay trong app.
- [ ] Cầu nối JSON-RPC tới `clangd` / `pyright` / `tsserver` trên VPS để hiện Autocomplete sâu & gạch đỏ lỗi thời gian thực.

---

## 3. Nhật ký Lỗi & Giải pháp (Errors Log)
| Lỗi / Rủi ro phát hiện sớm | Lần thử | Giải pháp đã áp dụng |
| :--- | :---: | :--- |
| Tên module Swift không được bắt đầu bằng chữ số (`3012`) | Phòng ngừa | Đặt `PRODUCT_MODULE_NAME: App3012` trong khi giữ nguyên `PRODUCT_NAME: "3012"` và `CFBundleDisplayName: "3012"`. |
| Xung đột phiên bản SPM giữa `TreeSitterLanguages` và `Runestone` | Phòng ngừa | Ghim chính xác commit `Runestone` (`00426ba...`) khớp 100% với `Package.swift` của `TreeSitterLanguages` (`4442182...`) kèm Xcode 16+ trên `macos-15`. |
| iOS đóng băng `localhost:5500` sau ~30s khi chuyển sang Safari | Phòng ngừa | Bổ sung `UIBackgroundModes: [audio]` + vòng lặp WAV im lặng (`mixWithOthers`, `volume = 0`) giữ Live Server luôn thức ngầm. |
