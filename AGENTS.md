# 3012 — AI-Native Mobile IDE for iOS

## Nguồn Ngữ Cảnh Gốc (Đọc ngay khi khởi động phiên mới)
Khi bắt đầu bất kỳ cuộc trò chuyện mới nào trong Workspace `C:\3012`, AI Agent **BẮT BUỘC** đọc 2 file sau trước khi hành động:
1. `BLUEPRINT.md` — Bản thiết kế kiến trúc tổng thể v2.0: Zen-First 90% vùng code, Live Server (`localhost:5500` + mở Safari chạy ngầm), Zero-Config 1-Tap Runner (C/C++/Python/Web/VPS), Hệ thống Extension lai (Open VSX `.vsix`), và **AI Coding Agent** ngay bên cạnh cửa sổ code.
2. `task_plan.md` — Trạng thái tiến độ hiện tại của từng Phase và danh sách việc cần làm tiếp theo.
3. *(Tham khảo lịch sử)*: Phiên khởi tạo `849a2041-4514-434a-8919-29735312ef89` và phiên nâng cấp kiến trúc v2 `4256e3f2-d93d-437d-ad84-31c8677edf74`.

## Tổng quan Dự án
- **Tên ứng dụng:** `3012` (`com.dev.app3012`)
- **Thư mục dự án trên máy:** `C:\3012`
- **Nền tảng mục tiêu:** iOS (tương thích tốt iOS 17.0+ đến iOS 27.0.1+)
- **Kiến trúc:** Hướng B — 100% Native `SwiftUI` + `UIKit` (`Runestone` + `Tree-sitter` + `Network.framework` Live Server + `SwiftTerm` + `Citadel SSH/SFTP`)
- **Đóng gói:** Tự động biên dịch **Unsigned `.ipa` (`3012-Unsigned.ipa`)** qua **GitHub Actions (`macos-latest` + `XcodeGen`)** từ máy Windows; người dùng có chứng chỉ `.p12` riêng để tự sign ngoài.
- **4 Trụ cột Trải nghiệm Đặc biệt:**
  1. **Zen-First 90% Code + Pro Coding Bar:** Vuốt cạnh mở Drawer, vuốt Trackpad di chuyển con trỏ, Pinch-to-Zoom cỡ chữ, đổi Theme/Font chuẩn VS Code.
  2. **Built-in Live Server (`http://127.0.0.1:5500`):** Có WebSocket Hot-Reload và chế độ **Background Keep-Alive** để vừa code trong `3012` vừa xem trực tiếp trên **Safari / Chrome** hoặc khung Split Preview nội bộ.
  3. **Zero-Config 1-Tap Run:** Chạy ngay C, C++, Python, JS, HTML không cần tự cài MinGW hay cấu hình PATH; hỗ trợ nối VPS tự động cài trọn bộ compiler (`gcc/g++/clang/python3/node`).
  4. **AI Coding Agent Cạnh Cửa Sổ Code:** Khung chat Agentic như Antigravity / Cursor / Copilot đọc hiểu toàn project, tự tạo/sửa file kèm bảng duyệt Diff (Accept/Reject).

## Quy tắc Kỹ thuật Quan trọng (Cho AI Agent)
1. **Không sửa tay `.xcodeproj`:** Mọi cấu hình target, thư viện Swift Package Manager (SPM), quyền hạn (`Info.plist`) phải khai báo trong `project.yml` (**XcodeGen**).
2. **Đảm bảo Build Xanh 100% trên GitHub Actions:** Kiểm tra chặt chẽ phiên bản SPM (`TreeSitterLanguages` `main` đi kèm `Runestone` commit tương thích) và đầy đủ `import` cho từng file `.swift`.
3. **Quản lý Tiến độ:** Luôn cập nhật `task_plan.md` sau mỗi hạng mục hoàn thành.
