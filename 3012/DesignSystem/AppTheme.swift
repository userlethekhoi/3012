import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(uiColor: .systemBlue)
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let failure = Color(uiColor: .systemRed)
    static let cardRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 18
    static let pagePadding: CGFloat = 16
    static let controlHeight: CGFloat = 48
}

enum AppInterfaceScale: Int, CaseIterable, Identifiable {
    case eighty = 0
    case ninety
    case ninetyFive
    case oneHundred
    case oneFifteen
    case oneThirty
    case oneFortyFive
    case oneSixtyFive
    case oneEightyFive
    case twoHundred

    static let minimum = AppInterfaceScale.eighty
    static let standard = AppInterfaceScale.oneHundred
    static let maximum = AppInterfaceScale.twoHundred

    var id: Int { rawValue }

    var percentage: Int {
        switch self {
        case .eighty: return 80
        case .ninety: return 90
        case .ninetyFive: return 95
        case .oneHundred: return 100
        case .oneFifteen: return 115
        case .oneThirty: return 130
        case .oneFortyFive: return 145
        case .oneSixtyFive: return 165
        case .oneEightyFive: return 185
        case .twoHundred: return 200
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .eighty: return .xSmall
        case .ninety: return .small
        case .ninetyFive: return .medium
        case .oneHundred: return .large
        case .oneFifteen: return .xLarge
        case .oneThirty: return .xxLarge
        case .oneFortyFive: return .xxxLarge
        case .oneSixtyFive: return .accessibility1
        case .oneEightyFive: return .accessibility2
        case .twoHundred: return .accessibility3
        }
    }
}

extension Font {
    static let technicalValue = Font.system(.footnote, design: .monospaced).weight(.medium)
    static let sessionLog = Font.system(.caption, design: .monospaced)
}

struct PremiumCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
    }
}

struct StatusBadge: View {
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 72, height: 72)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
