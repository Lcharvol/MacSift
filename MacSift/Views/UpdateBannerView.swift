import SwiftUI
import AppKit

/// Thin banner shown above MainView when a newer MacSift release is
/// available. Three states: offer download → show progress → reveal the
/// staged .app in Finder. The whole banner is dismissible per-version via
/// the × button.
struct UpdateBannerView: View {
    @ObservedObject var updateVM: UpdateViewModel

    var body: some View {
        if let info = updateVM.availableUpdate, updateVM.shouldShowBanner {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacSift \(info.latestVersion) is available")
                        .font(.callout.weight(.semibold))
                    Text(subtitle(for: info))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                actionButtons(for: info)

                Button {
                    withAnimation { updateVM.dismissBanner() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss until the next release")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.blue.opacity(0.10))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func actionButtons(for info: UpdateInfo) -> some View {
        switch updateVM.downloadState {
        case .idle:
            Button("Release notes") {
                if !NSWorkspace.shared.open(info.releaseURL) {
                    MacSiftLog.warning("Failed to open release URL: \(info.releaseURL.absoluteString)")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Button("Download update") {
                Task { await updateVM.startDownload() }
            }
            .controlSize(.small)

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall(let appURL):
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([appURL])
            }
            .controlSize(.small)

            Text("Drag into /Applications")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
            Button("Open release page") {
                if !NSWorkspace.shared.open(info.releaseURL) {
                    MacSiftLog.warning("Failed to open release URL: \(info.releaseURL.absoluteString)")
                }
            }
            .controlSize(.small)
        }
    }

    private func subtitle(for info: UpdateInfo) -> String {
        let size = info.downloadSizeBytes.formattedFileSize
        var parts = ["You have \(updateVM.currentVersion)", "\(size) download"]
        if let published = info.publishedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append(formatter.localizedString(for: published, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }
}
