import Foundation

struct TMSnapshot: Identifiable, Sendable {
    let id = UUID()
    let identifier: String
    let dateString: String

    var displayDate: String {
        let parts = dateString.split(separator: "-")
        guard parts.count >= 4 else { return dateString }
        return "\(parts[0])-\(parts[1])-\(parts[2]) \(parts[3].prefix(2)):\(parts[3].dropFirst(2).prefix(2))"
    }
}

enum TimeMachineService {
    static func parseSnapshots(from output: String) -> [TMSnapshot] {
        output
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("com.apple.TimeMachine.") }
            .compactMap { line -> TMSnapshot? in
                let identifier = line.trimmingCharacters(in: .whitespaces)
                let prefix = "com.apple.TimeMachine."
                let suffix = ".local"
                guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else { return nil }
                let dateString = String(identifier.dropFirst(prefix.count).dropLast(suffix.count))
                return TMSnapshot(identifier: identifier, dateString: dateString)
            }
    }

    static func listSnapshots() async throws -> [TMSnapshot] {
        let output = try await runTmutil(arguments: ["listlocalsnapshots", "/"])
        return parseSnapshots(from: output)
    }

    static func deleteSnapshot(dateString: String) async throws {
        _ = try await runTmutil(arguments: ["deletelocalsnapshots", dateString])
    }

    private static func runTmutil(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/tmutil")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Use terminationHandler so we don't block a thread waiting for
            // the subprocess to finish.
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: TMError.commandFailed(output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum TMError: Error, LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let output): "tmutil failed: \(output)"
            }
        }
    }
}
