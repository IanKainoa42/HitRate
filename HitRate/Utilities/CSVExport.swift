import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Lazily-exported CSV of every attempt. Rows are snapshotted as plain values
/// when the view builds (cheap); the string build + temp-file write only
/// happen when the share actually fires — never do file I/O in a SwiftUI body
/// (the old version rewrote the CSV to disk on every Home render).
struct CSVExportItem: Transferable {
    struct Row {
        let timestamp: Date
        let sessionStart: Date
        let group: String
        let outcome: String
    }

    let rows: [Row]
    let noun: String   // CSV header column for the bucket ("skill"/"group")

    init(sessions: [PracticeSession]) {
        noun = AppMode.current.noun
        rows = sessions
            .flatMap { s in
                s.sortedAttempts.map {
                    Row(timestamp: $0.timestamp, sessionStart: s.startedAt,
                        group: $0.group?.name ?? "",
                        outcome: $0.outcome.label($0.group?.kind ?? .stunt))
                }
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var hasData: Bool { !rows.isEmpty }

    private func write() throws -> URL {
        let iso = ISO8601DateFormatter()
        var csv = ["timestamp", "session_start", noun, "outcome"].map(Self.csvField).joined(separator: ",") + "\n"
        for r in rows {
            csv += [
                iso.string(from: r.timestamp),
                iso.string(from: r.sessionStart),
                r.group,
                r.outcome
            ].map(Self.csvField).joined(separator: ",") + "\n"
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitRate-\(f.string(from: .now)).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") ||
            escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            SentTransferredFile(try item.write())
        }
    }
}
