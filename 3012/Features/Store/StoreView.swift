import SwiftUI

struct StoreView: View {
    @State private var searchText = ""
    @State private var selectedCategory = "Tất cả"

    private let categories = ["Tất cả", "Giao diện", "Tiện ích"]

    private var filteredItems: [PatchSummary] {
        PatchSummary.previewItems.filter { item in
            let matchesCategory = selectedCategory == "Tất cả" || item.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.summary.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    hero
                    manualPatchEntry
                    categoryPicker
                    patchSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("3012")
            .searchable(text: $searchText, prompt: "Tìm patch")
            .refreshable {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private var manualPatchEntry: some View {
        NavigationLink {
            ManualPatchView()
        } label: {
            PremiumCard {
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(
                            AppTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patch thủ công")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Dùng file lớn từ Files, không cần đưa lên server.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Spacer()
                StatusBadge(title: "PREVIEW", color: .white)
            }
            Text("Kho patch mới, cập nhật độc lập với IPA.")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Catalog có chữ ký, tải nền và khôi phục an toàn sẽ được bổ sung theo roadmap.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.accent, Color(red: 0.09, green: 0.35, blue: 0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
        )
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 15)
                            .frame(height: 38)
                            .background(
                                selectedCategory == category
                                    ? AppTheme.accent
                                    : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var patchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Khám phá")
                .font(.title3.weight(.bold))
            ForEach(filteredItems) { item in
                PatchRow(item: item)
            }
        }
    }
}

private struct PatchRow: View {
    let item: PatchSummary

    var body: some View {
        PremiumCard {
            HStack(spacing: 14) {
                Image(systemName: item.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("v\(item.version) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
