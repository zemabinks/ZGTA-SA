// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Bounded transport for private structured diagnostics. Each complete record
/// has its own identity and checksum; a missing part is never a valid record.
enum NativeDiagnosticChunks {
    enum Failure: Error { case payload, encoding }
    static let payloadBytes = 512
    static let maximumRecordBytes = 128 * 1024
    static let maximumLineBytes = 920

    static func encode(_ data: Data, identifier: UUID = UUID()) throws -> [String] {
        guard !data.isEmpty, data.count <= maximumRecordBytes else { throw Failure.payload }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let count = (data.count + payloadBytes - 1) / payloadBytes
        return try (0..<count).map { part in
            let start = part * payloadBytes
            let body = data.subdata(in: start..<min(data.count, start + payloadBytes))
            let record: [String: Any] = ["id": identifier.uuidString.lowercased(),
                "part": part, "count": count, "sha256": checksum, "data": body.base64EncodedString()]
            let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
            guard encoded.count <= maximumLineBytes, let line = String(data: encoded, encoding: .utf8) else {
                throw Failure.encoding
            }
            return line
        }
    }
}
