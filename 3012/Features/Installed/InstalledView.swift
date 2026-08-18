import SwiftUI

struct InstalledView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "checkmark.seal.fill",
                title: "Chưa có patch đã cài",
                message: "Patch đã xác minh và cài đặt sẽ xuất hiện tại đây cùng trạng thái backup và khôi phục."
            )
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Đã cài")
        }
    }
}
