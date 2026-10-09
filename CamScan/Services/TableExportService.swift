import Foundation
import Vision

/// Finds tables on pages with `RecognizeDocumentsRequest` and exports them as CSV.
nonisolated enum TableExportService {
    /// Every table on the page as rows of cell strings.
    static func tables(in imageData: Data) async throws -> [[[String]]] {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: imageData)
        guard let document = observations.first?.document else { return [] }
        return document.tables.map { table in
            table.rows.map { row in row.map { $0.content.text.transcript } }
        }
    }

    /// RFC 4180 CSV; tables separated by an empty line. Starts with a BOM so Excel reads Cyrillic correctly.
    static func csv(_ tables: [[[String]]]) -> String {
        let body = tables.map { table in
            table.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        }.joined(separator: "\r\n\r\n")
        return "\u{FEFF}" + body
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
