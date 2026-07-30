import CryptoKit
import Foundation

enum SQLiteContentDigest {
    static let currentVersion = 1
    static let batchSize = 500

    static func digest(for legacyContentHash: String) -> Data {
        Data(SHA256.hash(data: Data(legacyContentHash.utf8)))
    }
}
