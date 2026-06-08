import Foundation

/// Exports jobs to CSV. Ports server/export.js exactly.
public enum ExportService {
    /// The 19 CSV columns in order, matching export.js CSV_COLUMNS.
    static let columns = [
        "job_number", "capture_id", "job_id", "status", "rating", "extraction_status",
        "company", "title", "location", "remote_type", "salary_min", "salary_max",
        "salary_currency", "salary_note", "application_url", "extraction_model",
        "source_url", "captured_at", "extracted_at"
    ]

    /// Returns a complete CSV string (headers + rows) for the given jobs.
    public static func jobsCSV(jobs: [Job]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [columns.joined(separator: ",")]

        for job in jobs {
            let capture = job.capture
            let sourceURL = capture?.canonicalURL ?? capture?.url ?? ""
            let capturedAt = capture.flatMap { iso.string(from: $0.capturedAt) } ?? ""
            let extractedAt = job.extractedAt.flatMap { iso.string(from: $0) } ?? ""

            let row: [String: String] = [
                "job_number": job.jobNumber.map(String.init) ?? "",
                "capture_id": capture?.id ?? "",
                "job_id": job.id,
                "status": job.status.rawValue,
                "rating": job.rating.map(String.init) ?? "",
                "extraction_status": job.extractionStatus.rawValue,
                "company": job.company ?? "",
                "title": job.title ?? "",
                "location": job.location ?? "",
                "remote_type": job.remoteType?.rawValue ?? "",
                "salary_min": job.salaryMin.map(String.init) ?? "",
                "salary_max": job.salaryMax.map(String.init) ?? "",
                "salary_currency": job.salaryCurrency ?? "",
                "salary_note": job.salaryNote ?? "",
                "application_url": job.applicationURL ?? "",
                "extraction_model": job.extractionModel ?? "",
                "source_url": sourceURL,
                "captured_at": capturedAt,
                "extracted_at": extractedAt
            ]

            let rowCSV = columns.map { col in escapeCsv(row[col] ?? "") }.joined(separator: ",")
            lines.append(rowCSV)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Write CSV to a file URL.
    public static func write(_ csv: String, to url: URL) throws {
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - RFC-4180 escaping

    /// Fields containing comma, quote, or newline are wrapped in double-quotes;
    /// internal double-quotes are doubled.
    static func escapeCsv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
