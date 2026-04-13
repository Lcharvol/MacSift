import SwiftUI
import AppKit
import QuickLookUI

/// Quick Look helper used by the inspector panel to preview files.
@MainActor
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreview()
    private var url: URL?

    static func show(url: URL) {
        shared.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            self.url as NSURL?
        }
    }
}
