# Hướng dẫn sử dụng 3012

## Trạng thái hiện tại

Phiên bản `0.1.0-dev` đã có transaction, backup/restore, tải nền và patch thủ công từ Files. Catalog production vẫn cần được cấu hình public key và storage trước khi bật kho online thật.

## Cài và mở bản phát triển

### Simulator

1. Clone repository và mở `3012.xcodeproj` bằng Xcode.
2. Chọn scheme `3012`.
3. Chọn một iPhone/iPad simulator iOS 16 trở lên.
4. Nhấn Run.

### Thiết bị thật

1. Chọn Apple Developer Team trong Signing & Capabilities.
2. Đổi bundle identifier nếu provisioning profile của bạn yêu cầu.
3. Chọn thiết bị và Run.

Artifact GitHub Actions hiện là unsigned nên không thể cài trực tiếp nếu chưa được ký bằng chứng chỉ/profile phù hợp.

## Các tab

- **Kho:** mock catalog và lối vào Patch thủ công.
- **Đã cài:** lịch sử patch thủ công, backup và nút khôi phục.
- **Tải xuống:** background download, pause/resume/retry và import `.3012pkg`.
- **Cài đặt:** theme System/Light/Dark, channel Stable/Beta và thông tin repository.

## Khi catalog online được phát hành

Luồng dự kiến:

1. App tải và xác minh catalog.
2. Người dùng xem compatibility, publisher, dung lượng và thay đổi dự kiến.
3. App kiểm tra dung lượng trống rồi tải package xuống file tạm.
4. App xác minh chữ ký và digest.
5. Người dùng xác nhận import/apply.
6. App tạo backup và receipt trước khi thay đổi.
7. Người dùng có thể restore từ tab Đã cài.

## Patch thủ công cho file lớn

1. Vào **Kho → Patch thủ công**.
2. Đặt tên patch và chọn thư mục đích bằng Files.
3. Chọn một hoặc nhiều file thay thế. File có thể lớn; 3012 đọc theo chunk thay vì nạp toàn bộ vào RAM.
4. Với mỗi file, nhập relative path tính từ thư mục đích và chọn **Thay file có sẵn** hoặc **Tạo file mới**.
5. Kiểm tra lại dung lượng, đường dẫn rồi chọn **Kiểm tra và patch**.
6. 3012 tạo package cục bộ ký tạm thời, xác minh SHA-256, tạo backup/journal và mới bắt đầu ghi file.
7. Khôi phục từ tab **Đã cài**. App từ chối restore nếu file đã patch bị thay đổi tiếp, để không ghi đè dữ liệu mới.

Chỉ chọn thư mục và file mà bạn có quyền sửa. Patch thủ công không dùng server và không cung cấp khả năng vượt sandbox; quyền truy cập đến từ Files picker của iOS.
