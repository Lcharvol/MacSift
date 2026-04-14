import SwiftUI

/// Sidebar volume picker. Shown above the category list when the user has
/// more than one volume mounted. Selecting "All volumes" (nil) shows merged
/// totals across every disk; selecting a specific volume filters the whole
/// results screen to that disk's files only.
struct VolumePickerView: View {
    let volumes: [Volume]
    let sizeByVolume: [String: Int64]
    @Binding var selectedVolumeID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Volumes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            VStack(spacing: 2) {
                volumeButton(
                    label: "All volumes",
                    iconName: "externaldrive.connected.to.line.below",
                    size: sizeByVolume.values.reduce(0, +),
                    id: nil,
                    subtitle: "\(volumes.count) mounted"
                )
                ForEach(volumes) { volume in
                    volumeButton(
                        label: volume.name,
                        iconName: volume.isBoot ? "laptopcomputer" : "externaldrive",
                        size: sizeByVolume[volume.id] ?? 0,
                        id: volume.id,
                        subtitle: capacitySubtitle(for: volume)
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.bottom, 6)
    }

    private func volumeButton(label: String, iconName: String, size: Int64, id: String?, subtitle: String) -> some View {
        let isSelected = selectedVolumeID == id
        return Button {
            selectedVolumeID = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                Spacer()
                if size > 0 {
                    Text(size.formattedFileSize)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func capacitySubtitle(for volume: Volume) -> String {
        guard volume.totalCapacity > 0 else {
            return volume.isBoot ? "Startup disk" : "External"
        }
        let free = volume.availableCapacity.formattedFileSize
        let total = volume.totalCapacity.formattedFileSize
        return "\(free) free of \(total)"
    }
}
