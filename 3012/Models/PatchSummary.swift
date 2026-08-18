import Foundation

struct PatchSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let version: String
    let category: String
    let symbol: String
    let size: Int64
    let isFeatured: Bool

    static let previewItems: [PatchSummary] = [
        PatchSummary(
            id: "appearance-sample",
            name: "Appearance Sample",
            summary: "Gói minh họa giao diện cho catalog 3012.",
            version: "1.0.0",
            category: "Giao diện",
            symbol: "paintbrush.pointed.fill",
            size: 14_680_064,
            isFeatured: true
        ),
        PatchSummary(
            id: "configuration-sample",
            name: "Configuration Sample",
            summary: "Mẫu cấu hình an toàn dùng để phát triển UI.",
            version: "1.0.0",
            category: "Tiện ích",
            symbol: "slider.horizontal.3",
            size: 2_097_152,
            isFeatured: false
        )
    ]
}
