import SwiftUI

/// A visually rich preview of the Year Comparison feature, shown to free users.
/// Uses mock data that mimics the real YearComparisonView layout with a blur overlay + CTA.
struct YearComparePreview: View {
    @EnvironmentObject private var store: StoreService
    let playerName: String
    let onUnlock: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Mock comparison content stays visible (blurred) as the hook.
            mockContent
                .blur(radius: 5)
                .clipped()

            BlurGateUnlock(
                headline: "See how \(playerName) evolved season to season",
                trigger: .yearCompare
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Mock Content (looks like the real YearComparisonView)

    private var mockContent: some View {
        VStack(spacing: 12) {
            // Mock year picker
            mockYearPicker

            // Mock aggregate comparison
            mockCategoryCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var mockYearPicker: some View {
        HStack(spacing: 12) {
            mockYearButton(label: "2025-26", subtitle: "Recent")
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HardwoodPalette.inkTertiary)
            mockYearButton(label: "2024-25", subtitle: "Prior")
        }
        .padding(16)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private func mockYearButton(label: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(HardwoodType.statLarge)
                .foregroundStyle(HardwoodPalette.ink)
            Text(subtitle)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(HardwoodPalette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
    }

    private var mockCategoryCard: some View {
        VStack(spacing: 0) {
            HardwoodSubSectionBar(title: "STANDARD STATS")
            mockHeader

            mockRow(label: "PPG", priorVal: "23.1", recentVal: "26.8")
            mockRow(label: "RPG", priorVal: "5.2", recentVal: "5.9")
            mockRow(label: "APG", priorVal: "6.4", recentVal: "7.3")
            mockRow(label: "FG", priorVal: "512/1,120", recentVal: "611/1,298")
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private var mockHeader: some View {
        HStack(spacing: 0) {
            Text("STAT")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("2024-25")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 72)
            Text("2025-26")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 72)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: 28)
        .background(HardwoodPalette.surfaceAlt)
    }

    private func mockRow(
        label: String,
        priorVal: String,
        recentVal: String
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(HardwoodType.body)
                .foregroundStyle(HardwoodPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            mockYearValue(value: priorVal, isFaded: true)
                .frame(width: 72)

            mockYearValue(value: recentVal, isFaded: false)
                .frame(width: 72)
        }
        .frame(height: 48)
        .padding(.horizontal, HardwoodGeo.padInline)
        .background(HardwoodPalette.surface)
        .overlay(
            Rectangle()
                .fill(HardwoodPalette.divider)
                .frame(height: HardwoodGeo.hairline),
            alignment: .bottom
        )
    }

    private func mockYearValue(value: String, isFaded: Bool) -> some View {
        Text(value)
            .font(HardwoodType.statSmall)
            .foregroundStyle(isFaded ? HardwoodPalette.inkTertiary : HardwoodPalette.court)
            .lineLimit(1)
    }
}

#Preview {
    YearComparePreview(playerName: "Jalen Brunson", onUnlock: {})
        .environmentObject(StoreService.shared)
}
