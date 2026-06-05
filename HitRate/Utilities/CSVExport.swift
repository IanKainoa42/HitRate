import Foundation

enum CSVExport {
    /// Writes every attempt to a temp CSV and returns its URL (nil if no data).
    static func write(sessions: [PracticeSession]) -> URL? {
        let all = sessions.flatMap { s in
            s.sortedAttempts.map { (session: s, attempt: $0) }
        }
        guard !all.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        var csv = "timestamp,session_start,group,outcome\n"
        for row in all.sorted(by: { $0.attempt.timestamp < $1.attempt.timestamp }) {
            let group = (row.attempt.group?.name ?? "").replacingOccurrences(of: ",", with: " ")
            csv += "\(iso.string(from: row.attempt.timestamp)),\(iso.string(from: row.session.startedAt)),\(group),\(row.attempt.outcome.label)\n"
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitRate-\(f.string(from: .now)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
