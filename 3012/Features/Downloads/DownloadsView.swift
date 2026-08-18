import SwiftUI

struct DownloadsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "arrow.down.circle.fill",
                title: "Không có lượt tải",
                message: "Các package đang tải, tạm dừng hoặc chờ xác minh sẽ được quản lý tại đây."
            )
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Tải xuống")
        }
    }
}
