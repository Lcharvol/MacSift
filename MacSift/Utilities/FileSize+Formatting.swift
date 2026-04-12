import Foundation

extension Int64 {
    var formattedFileSize: String {
        let units: [(String, Int64)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1024),
        ]

        for (label, threshold) in units {
            if self >= threshold {
                let value = Double(self) / Double(threshold)
                return String(format: "%.1f %@", value, label)
            }
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        let formatted = formatter.string(from: NSNumber(value: self)) ?? "\(self)"
        return "\(formatted) B"
    }
}
