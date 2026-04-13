import SwiftUI

/// The welcome screen shown before the first scan. Pure function of its
/// inputs — takes a callback for the scan button and a flag for the
/// Full Disk Access banner.
struct WelcomeView: View {
    let hasFullDiskAccess: Bool
    let onStartScan: () -> Void
    let onOpenFullDiskAccess: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(28)
                .glassEffect(.regular, in: Circle())

            VStack(spacing: 6) {
                Text("Welcome to MacSift")
                    .font(.largeTitle.weight(.semibold))
                Text("Discover what's taking up space, with full transparency.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !hasFullDiskAccess {
                fullDiskAccessBanner
                    .padding(.top, 4)
            }

            Button {
                onStartScan()
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.top, 4)

            Text("Tip: drop any folder on the window to scan just that folder.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Full Disk Access Required")
                    .font(.callout.weight(.medium))
                Text("Some system files won't be scanned without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access") { onOpenFullDiskAccess() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 480)
    }
}
