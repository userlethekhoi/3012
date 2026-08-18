# Hướng dẫn sử dụng 3012

## Trạng thái hiện tại

Phiên bản `0.1.0-dev` là UI preview dành cho phát triển. Nó chưa tải hoặc apply package thật.

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

- **Kho:** mock catalog để kiểm tra layout, search và category filter.
- **Đã cài:** empty state cho thư viện package tương lai.
- **Tải xuống:** empty state cho background download manager tương lai.
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

Tài liệu sẽ được cập nhật cùng lúc với tính năng; không làm theo luồng dự kiến trên một bản chưa hỗ trợ.
