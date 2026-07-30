import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import ClipEase

@Test func enterprisePerformanceBenchmarkDriver() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let action = environment["CLIPEASE_BENCHMARK_ACTION"] else {
        return
    }
    let context = try EnterprisePerformanceBenchmarkContext(environment: environment)
    switch action {
    case "prepare":
        try context.prepare()
    case "warmup":
        _ = try context.sample(iteration: -1)
    case "sample":
        guard let rawIteration = environment["CLIPEASE_BENCHMARK_ITERATION"],
              let iteration = Int(rawIteration),
              iteration >= 0 else {
            throw EnterprisePerformanceBenchmarkError.invalidEnvironment(
                "CLIPEASE_BENCHMARK_ITERATION must be a non-negative integer"
            )
        }
        let row = try context.sample(iteration: iteration)
        try context.append(row: row)
    default:
        throw EnterprisePerformanceBenchmarkError.invalidEnvironment(
            "unsupported CLIPEASE_BENCHMARK_ACTION \(action)"
        )
    }
}

private enum EnterprisePerformanceBenchmarkError: Error, CustomStringConvertible {
    case invalidEnvironment(String)
    case invalidFixture(String)
    case invalidResult(String)

    var description: String {
        switch self {
        case .invalidEnvironment(let message),
             .invalidFixture(let message),
             .invalidResult(let message):
            message
        }
    }
}

fileprivate struct EnterpriseBenchmarkItemRecord: Decodable {
    let id: UUID
    let type: String
    let plainText: String
    let sourceBundleID: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
    let isPinned: Bool
    let searchToken: String
}

fileprivate enum EnterpriseBenchmarkFixtureDatabaseLoader {
    private static let batchSize = 40
    private static let itemPlaceholder = "("
        + Array(repeating: "?", count: 20).joined(separator: ",")
        + ")"
    private static let itemInsertSQL = """
        INSERT INTO clipboard_items (
            id, type, plain_text, url, link_title, link_subtitle,
            source_app_name, source_bundle_id, source_icon_name,
            source_icon_file_name, header_color, created_at, updated_at,
            last_used_at, pinned_at, is_pinned, is_deleted, last_edited_at,
            group_sort_order, content_hash
        ) VALUES
        """

    private struct PreparedRecord {
        let itemValues: [SQLiteValue]
        let searchValues: [SQLiteValue]
        let assetValues: [SQLiteValue]?
        let fileValues: [SQLiteValue]?
    }

    static func load(
        records: [EnterpriseBenchmarkItemRecord],
        fixtureID: String,
        databaseURL: URL
    ) throws {
        let store = SQLiteClipboardStore(databaseURL: databaseURL)
        try store.initialize()

        let database = try SQLiteConnection(url: databaseURL)
        defer { database.close() }
        try execute("PRAGMA foreign_keys = ON", database: database)
        try execute("PRAGMA synchronous = OFF", database: database)
        try execute("BEGIN IMMEDIATE TRANSACTION", database: database)

        do {
            for start in stride(from: 0, to: records.count, by: batchSize) {
                let end = min(start + batchSize, records.count)
                let prepared = records[start..<end].map {
                    prepare($0, fixtureID: fixtureID)
                }
                let itemPlaceholders = Array(
                    repeating: itemPlaceholder,
                    count: prepared.count
                ).joined(separator: ",")
                try database.execute(
                    "\(itemInsertSQL) \(itemPlaceholders)",
                    values: prepared.flatMap(\.itemValues)
                )
                let searchPlaceholders = Array(
                    repeating: "(?, ?)",
                    count: prepared.count
                ).joined(separator: ",")
                try database.execute(
                    """
                    INSERT INTO clipboard_items_fts (item_id, search_text)
                    VALUES \(searchPlaceholders)
                    """,
                    values: prepared.flatMap(\.searchValues)
                )
                let assets = prepared.compactMap(\.assetValues)
                if !assets.isEmpty {
                    let placeholders = Array(
                        repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        count: assets.count
                    ).joined(separator: ",")
                    try database.execute(
                        """
                        INSERT INTO item_assets (
                            id, item_id, asset_type, file_name,
                            original_file_name, width, height, byte_size, created_at
                        ) VALUES \(placeholders)
                        """,
                        values: assets.flatMap { $0 }
                    )
                }
                let files = prepared.compactMap(\.fileValues)
                if !files.isEmpty {
                    let placeholders = Array(
                        repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        count: files.count
                    ).joined(separator: ",")
                    try database.execute(
                        """
                        INSERT INTO clipboard_item_files (
                            id, item_id, display_order, file_path, file_name,
                            file_extension, uti_or_content_type, byte_size,
                            modified_at, is_directory, is_alias, path_status,
                            last_checked_at, created_at
                        ) VALUES \(placeholders)
                        """,
                        values: files.flatMap { $0 }
                    )
                }
            }
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }

        try execute("PRAGMA wal_checkpoint(TRUNCATE)", database: database)
    }

    private static func prepare(
        _ record: EnterpriseBenchmarkItemRecord,
        fixtureID: String
    ) -> PreparedRecord {
        let type = ClipboardItemType(rawValue: record.type) ?? .text
        let text = type == .color
            ? "#8899AA"
            : "\(record.plainText) \(record.searchToken)"
        let sourceAppName = "Fixture \(record.sourceBundleID.suffix(2))"
        let url = type == .link
            ? "https://fixture.clipease.invalid/\(record.id.uuidString)"
            : nil
        let linkTitle = type == .link
            ? "Fixture \(record.id.uuidString)"
            : nil
        let filePath = type == .file
            ? "/synthetic/\(fixtureID)/\(record.id.uuidString).txt"
            : nil
        let fileName = type == .file
            ? "\(record.id.uuidString).txt"
            : nil
        let searchText = [
            text,
            linkTitle,
            url,
            fileName ?? "",
            filePath ?? "",
            "",
            "",
            "",
            "",
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        let assetValues: [SQLiteValue]?
        switch record.type {
        case "image":
            assetValues = [
                .text(record.id.uuidString),
                .text(record.id.uuidString),
                .text("image"),
                .text("\(record.id.uuidString).png"),
                .null,
                .int(640),
                .int(360),
                .null,
                .double(record.createdAt),
            ]
        case "richText":
            assetValues = [
                .text(record.id.uuidString),
                .text(record.id.uuidString),
                .text("rich_text"),
                .text("\(record.id.uuidString).rtf"),
                .null,
                .null,
                .null,
                .null,
                .double(record.createdAt),
            ]
        default:
            assetValues = nil
        }
        let fileValues: [SQLiteValue]?
        if let filePath, let fileName {
            fileValues = [
                .text(record.id.uuidString),
                .text(record.id.uuidString),
                .int(0),
                .text(filePath),
                .text(fileName),
                .text("txt"),
                .null,
                .int(text.utf8.count),
                .null,
                .bool(false),
                .bool(false),
                .text(ClipboardFilePathStatus.available.rawValue),
                .null,
                .double(record.createdAt),
            ]
        } else {
            fileValues = nil
        }
        return PreparedRecord(
            itemValues: [
                .text(record.id.uuidString),
                .text(type.rawValue),
                .text(text),
                .optionalText(url),
                .optionalText(linkTitle),
                .optionalText(url),
                .text(sourceAppName),
                .text(record.sourceBundleID),
                .text("app.fill"),
                .null,
                .text("#2E8CFF"),
                .double(record.createdAt),
                .double(record.createdAt),
                .null,
                .optionalDouble(record.isPinned ? record.updatedAt : nil),
                .bool(record.isPinned),
                .int(0),
                .null,
                .null,
                .text(type == .image ? record.id.uuidString : text),
            ],
            searchValues: [.text(record.id.uuidString), .text(searchText)],
            assetValues: assetValues,
            fileValues: fileValues
        )
    }

    private static func execute(
        _ sql: String,
        database: SQLiteConnection
    ) throws {
        do {
            try database.execute(sql)
        } catch {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "benchmark fixture SQL failed: \(error.localizedDescription)"
            )
        }
    }
}

private struct EnterprisePerformanceBenchmarkContext {
    struct Manifest: Decodable {
        let schemaVersion: Int
        let fixtures: [Fixture]
    }

    struct Fixture: Decodable {
        struct StressProfiles: Decodable {
            let burst8MiBCount: Int
            let maximumImagePixels: Int
            let maximumPDFPages: Int
        }

        let id: String
        let kind: String
        let itemCount: Int
        let relativePath: String
        let fileCount: Int
        let payloadByteCount: Int
        let treeSHA256: String
        let assetKinds: [String]?
        let stressProfiles: StressProfiles?
    }

    struct AssetReference: Decodable {
        let kind: String
        let relativePath: String
        let byteCount: Int
        let sha256: String
        let profile: String?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let pageCount: Int?
    }

    struct Measurement: Encodable {
        let durationMS: Double
        let rssMiB: Double
        let cpuTimeMS: Double
    }

    struct SampleRow: Encodable {
        let iteration: Int
        let metrics: [String: Measurement]
    }

    let fixtureRoot: URL
    let workRoot: URL
    let rawOutputURL: URL
    let manifest: Manifest

    init(environment: [String: String]) throws {
        guard let manifestPath = environment["CLIPEASE_PERFORMANCE_FIXTURE_MANIFEST"],
              let fixtureRootPath = environment["CLIPEASE_PERFORMANCE_FIXTURE_ROOT"],
              let workRootPath = environment["CLIPEASE_BENCHMARK_WORK_ROOT"],
              let rawOutputPath = environment["CLIPEASE_BENCHMARK_RAW_OUTPUT"] else {
            throw EnterprisePerformanceBenchmarkError.invalidEnvironment(
                "benchmark manifest, fixture root, work root, and raw output are required"
            )
        }
        fixtureRoot = URL(fileURLWithPath: fixtureRootPath, isDirectory: true)
        workRoot = URL(fileURLWithPath: workRootPath, isDirectory: true)
        rawOutputURL = URL(fileURLWithPath: rawOutputPath)
        manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
        )
        guard manifest.schemaVersion == 2 else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "fixture manifest schemaVersion must be 2"
            )
        }
        let expected = ["S1K": 1_000, "T10K": 10_000, "M100K": 100_000, "A3K": 3_000]
        guard Dictionary(uniqueKeysWithValues: manifest.fixtures.map { ($0.id, $0.itemCount) }) == expected else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "fixture IDs or item counts do not match the enterprise contract"
            )
        }
        guard manifest.fixtures.allSatisfy({
            $0.treeSHA256.count == 64
                && $0.fileCount > 0
                && $0.payloadByteCount > 0
        }) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "fixture manifest must include actual tree hashes and payload sizes"
            )
        }
        guard let assetFixture = manifest.fixtures.first(where: { $0.id == "A3K" }),
              assetFixture.stressProfiles?.burst8MiBCount == 30,
              assetFixture.stressProfiles?.maximumImagePixels == 32 * 1_024 * 1_024,
              assetFixture.stressProfiles?.maximumPDFPages == 25 else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "A3K stress profile must include 30x8MiB, 32MP, and 25-page limits"
            )
        }
    }

    func prepare() throws {
        try FileManager.default.createDirectory(
            at: workRoot,
            withIntermediateDirectories: true
        )
        for fixture in manifest.fixtures {
            let fixtureURL = try validatedFixtureURL(for: fixture)
            guard try Self.treeSHA256(root: fixtureURL) == fixture.treeSHA256 else {
                throw EnterprisePerformanceBenchmarkError.invalidFixture(
                    "\(fixture.id) tree hash does not match its manifest"
                )
            }
        }
        for fixtureID in ["S1K", "T10K", "M100K"] {
            let fixture = try requiredFixture(fixtureID)
            let databaseURL = self.databaseURL(for: fixtureID)
            guard !FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw EnterprisePerformanceBenchmarkError.invalidEnvironment(
                    "benchmark work directory must be fresh: \(databaseURL.lastPathComponent)"
                )
            }
            let records = try itemRecords(fixture: fixture)
            try EnterpriseBenchmarkFixtureDatabaseLoader.load(
                records: records,
                fixtureID: fixtureID,
                databaseURL: databaseURL
            )
            let database = try SQLiteConnection(url: databaseURL)
            let storedCount: Int
            let indexedCount: Int
            let assetCount: Int
            let fileCount: Int
            do {
                storedCount = try database.queryInt(
                    "SELECT COUNT(*) FROM clipboard_items"
                )
                indexedCount = try database.queryInt(
                    "SELECT COUNT(*) FROM clipboard_items_fts"
                )
                assetCount = try database.queryInt(
                    "SELECT COUNT(*) FROM item_assets"
                )
                fileCount = try database.queryInt(
                    "SELECT COUNT(*) FROM clipboard_item_files"
                )
            } catch {
                database.close()
                throw error
            }
            database.close()
            let expectedAssetCount = records.count {
                $0.type == "image" || $0.type == "richText"
            }
            let expectedFileCount = records.count { $0.type == "file" }
            guard storedCount == fixture.itemCount,
                  indexedCount == fixture.itemCount,
                  assetCount == expectedAssetCount,
                  fileCount == expectedFileCount else {
                throw EnterprisePerformanceBenchmarkError.invalidResult(
                    "\(fixtureID) preparation item/index/asset/file counts "
                        + "\(storedCount)/\(indexedCount)/\(assetCount)/\(fileCount) "
                        + "did not match \(fixture.itemCount)/\(fixture.itemCount)"
                        + "/\(expectedAssetCount)/\(expectedFileCount)"
                )
            }
        }
        try validateAssetFixture()
    }

    func sample(iteration: Int) throws -> SampleRow {
        var metrics: [String: Measurement] = [:]

        let startupStore = SQLiteClipboardStore(databaseURL: databaseURL(for: "S1K"))
        metrics["startup_snapshot_s1k"] = try measure {
            let snapshot = try startupStore.loadSnapshot(itemLimit: 1_000, offset: 0)
            guard snapshot.items.count == 1_000 else {
                throw EnterprisePerformanceBenchmarkError.invalidResult("S1K startup load was incomplete")
            }
        }

        let dailyStore = SQLiteClipboardStore(databaseURL: databaseURL(for: "T10K"))
        metrics["search_t10k_sqlite"] = try measure {
            let items = try dailyStore.searchItems(
                ClipboardSearchQuery(text: "deterministic performance item 9999", limit: 50)
            )
            guard !items.isEmpty else {
                throw EnterprisePerformanceBenchmarkError.invalidResult("T10K search returned no results")
            }
        }

        var updatedItem = try dailyStore.loadItems(limit: 1, offset: 0)[0]
        updatedItem.isPinned.toggle()
        updatedItem.pinnedAt = updatedItem.isPinned ? Date(timeIntervalSince1970: 1_800_000_000) : nil
        metrics["upsert_t10k"] = try measure {
            try dailyStore.upsertItem(updatedItem, deleting: [], groups: [])
        }

        let permanentStore = SQLiteClipboardStore(databaseURL: databaseURL(for: "M100K"))
        metrics["fts_cold_m100k"] = try measure {
            let items = try permanentStore.searchItems(
                ClipboardSearchQuery(text: "deterministic performance item 99999", limit: 50)
            )
            guard !items.isEmpty else {
                throw EnterprisePerformanceBenchmarkError.invalidResult(
                    "M100K connection-cold FTS returned no results"
                )
            }
        }
        metrics["fts_hot_m100k"] = try measure {
            let items = try permanentStore.searchItems(
                ClipboardSearchQuery(text: "deterministic performance item 99999", limit: 50)
            )
            guard !items.isEmpty else {
                throw EnterprisePerformanceBenchmarkError.invalidResult(
                    "M100K hot FTS returned no results"
                )
            }
        }
        let pageCursor = try stableM100KCursor()
        metrics["page_1k_m100k"] = try measure {
            try loadStableM100KPage(after: pageCursor)
        }

        metrics["asset_scan_a3k"] = try measure {
            let references = try assetReferences()
            guard references.count == 3_000 else {
                throw EnterprisePerformanceBenchmarkError.invalidResult("A3K reference count changed")
            }
            let totalBytes = try references.reduce(into: 0) { result, reference in
                let url = try assetURL(for: reference)
                result += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            }
            guard totalBytes > 0 else {
                throw EnterprisePerformanceBenchmarkError.invalidResult("A3K assets are empty")
            }
        }
        metrics["asset_decode_a3k"] = try measure {
            try decodeAssetBatch(iteration: iteration)
        }

        return SampleRow(iteration: iteration, metrics: metrics)
    }

    func append(row: SampleRow) throws {
        let data = try JSONEncoder().encode(row) + Data([0x0A])
        let directory = rawOutputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: rawOutputURL.path) {
            try data.write(to: rawOutputURL, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: rawOutputURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func measure(_ operation: () throws -> Void) throws -> Measurement {
        let cpuStartedAt = try Self.processCPUTimeMS()
        let startedAt = CFAbsoluteTimeGetCurrent()
        try operation()
        let endedAt = CFAbsoluteTimeGetCurrent()
        let cpuEndedAt = try Self.processCPUTimeMS()
        let rssMiB = try Self.currentResidentMemoryMiB()
        return Measurement(
            durationMS: (endedAt - startedAt) * 1_000,
            rssMiB: rssMiB,
            cpuTimeMS: max(0, cpuEndedAt - cpuStartedAt)
        )
    }

    private func requiredFixture(_ id: String) throws -> Fixture {
        guard let fixture = manifest.fixtures.first(where: { $0.id == id }) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture("missing \(id) fixture")
        }
        return fixture
    }

    private func databaseURL(for fixtureID: String) -> URL {
        workRoot.appendingPathComponent("\(fixtureID).sqlite")
    }

    private func itemRecords(
        fixture: Fixture
    ) throws -> [EnterpriseBenchmarkItemRecord] {
        let url = try validatedFixtureURL(for: fixture)
            .appendingPathComponent("items.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map {
                try JSONDecoder().decode(
                    EnterpriseBenchmarkItemRecord.self,
                    from: Data($0.utf8)
                )
            }
        guard records.count == fixture.itemCount else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "\(fixture.id) record count does not match its manifest"
            )
        }
        return records
    }

    private func assetReferences() throws -> [AssetReference] {
        let fixture = try requiredFixture("A3K")
        let url = try validatedFixtureURL(for: fixture)
            .appendingPathComponent("assets.jsonl")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map {
                try JSONDecoder().decode(AssetReference.self, from: Data($0.utf8))
            }
    }

    private func assetURL(for reference: AssetReference) throws -> URL {
        let fixture = try requiredFixture("A3K")
        let fixtureURL = try validatedFixtureURL(for: fixture)
        let url = fixtureURL.appendingPathComponent(reference.relativePath)
        let standardizedRoot = fixtureURL.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "asset reference escaped fixture root"
            )
        }
        return url
    }

    private func validateAssetFixture() throws {
        let references = try assetReferences()
        guard references.count == 3_000 else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "A3K must contain exactly 3,000 asset references"
            )
        }
        let kinds = Set(references.map(\.kind))
        guard kinds == Set(["png", "heic", "pdf", "rtf", "txt"]) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "A3K must contain PNG, HEIC, PDF, RTF, and file assets"
            )
        }
        guard references.filter({ $0.profile == "burst8MiB" }).count == 30,
              references.filter({ $0.profile == "burst8MiB" }).allSatisfy({
                  $0.byteCount >= 8 * 1_024 * 1_024
              }),
              references.contains(where: {
                  $0.profile == "image32MP"
                      && ($0.pixelWidth ?? 0) * ($0.pixelHeight ?? 0)
                          == 32 * 1_024 * 1_024
              }),
              references.contains(where: {
                  $0.profile == "pdf25Pages" && $0.pageCount == 25
              }) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "A3K stress assets do not match their declared profile"
            )
        }
        for reference in references {
            let url = try assetURL(for: reference)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  values.fileSize == reference.byteCount,
                  try Self.sha256(url: url) == reference.sha256 else {
                throw EnterprisePerformanceBenchmarkError.invalidFixture(
                    "A3K asset hash or size mismatch"
                )
            }
            if let pixelWidth = reference.pixelWidth,
               let pixelHeight = reference.pixelHeight {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(
                        source,
                        0,
                        nil
                      ) as? [CFString: Any],
                      properties[kCGImagePropertyPixelWidth] as? Int == pixelWidth,
                      properties[kCGImagePropertyPixelHeight] as? Int == pixelHeight else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture(
                        "A3K image metadata does not match the declared dimensions"
                    )
                }
            }
            if let pageCount = reference.pageCount {
                guard PDFDocument(url: url)?.pageCount == pageCount else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture(
                        "A3K PDF page count does not match the declaration"
                    )
                }
            }
        }
    }

    private func decodeAssetBatch(iteration: Int) throws {
        let references = try assetReferences()
        let batchSize = 25
        let start = max(0, iteration) * batchSize % references.count
        for offset in 0..<batchSize {
            let reference = references[(start + offset) % references.count]
            let url = try assetURL(for: reference)
            switch reference.kind {
            case "png", "heic":
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 256,
                            kCGImageSourceCreateThumbnailWithTransform: true
                        ] as CFDictionary
                      ) != nil else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture(
                        "ImageIO could not decode \(reference.kind)"
                    )
                }
            case "pdf":
                guard let document = PDFDocument(url: url),
                      document.pageCount == (reference.pageCount ?? 1) else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture(
                        "PDFKit could not decode deterministic PDF"
                    )
                }
            case "rtf":
                var documentAttributes: NSDictionary?
                let value = try NSAttributedString(
                    url: url,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: &documentAttributes
                )
                guard value.length > 0 else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture("RTF was empty")
                }
            case "txt":
                guard try !Data(contentsOf: url, options: .mappedIfSafe).isEmpty else {
                    throw EnterprisePerformanceBenchmarkError.invalidFixture("file asset was empty")
                }
            default:
                throw EnterprisePerformanceBenchmarkError.invalidFixture(
                    "unsupported A3K kind \(reference.kind)"
                )
            }
        }
    }

    private func stableM100KCursor() throws -> (createdAt: Double, identifier: String) {
        let databaseURL = databaseURL(for: "M100K")
        let database = try SQLiteConnection(url: databaseURL)
        defer { database.close() }
        let cursorRows = try database.query(
            """
            SELECT created_at, id
            FROM clipboard_items
            WHERE is_deleted = 0 AND is_pinned = 0
            ORDER BY created_at DESC, id DESC
            LIMIT 1 OFFSET 50000
            """
        )
        guard let cursor = cursorRows.first else {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "M100K stable-page cursor was unavailable"
            )
        }
        return (
            createdAt: cursor.requiredDouble("created_at"),
            identifier: cursor.requiredText("id")
        )
    }

    private func loadStableM100KPage(
        after cursor: (createdAt: Double, identifier: String)
    ) throws {
        let databaseURL = databaseURL(for: "M100K")
        let database = try SQLiteConnection(url: databaseURL)
        defer { database.close() }
        let rows = try database.query(
            """
            SELECT id
            FROM clipboard_items
            WHERE is_deleted = 0
              AND is_pinned = 0
              AND (
                created_at < ?
                OR (created_at = ? AND id < ?)
              )
            ORDER BY created_at DESC, id DESC
            LIMIT 1000
            """,
            values: [
                .double(cursor.createdAt),
                .double(cursor.createdAt),
                .text(cursor.identifier),
            ]
        )
        let identifiers = rows.compactMap {
            UUID(uuidString: $0.requiredText("id"))
        }
        guard identifiers.count == 1_000 else {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "M100K stable keyset page returned \(identifiers.count) IDs"
            )
        }
        let items = try SQLiteItemDAO.loadItems(
            withOrderedIDs: identifiers,
            orderSQL: "clipboard_items.created_at DESC, clipboard_items.id DESC",
            in: database
        )
        guard items.count == 1_000 else {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "M100K stable keyset page materialized \(items.count) items"
            )
        }
    }

    private func validatedFixtureURL(for fixture: Fixture) throws -> URL {
        let root = fixtureRoot.standardizedFileURL
        let candidate = root
            .appendingPathComponent(fixture.relativePath, isDirectory: true)
            .standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "\(fixture.id) relativePath escaped the fixture root"
            )
        }
        return candidate
    }

    private static func sha256(url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func treeSHA256(root: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw EnterprisePerformanceBenchmarkError.invalidFixture(
                "could not enumerate fixture tree"
            )
        }
        let files = enumerator.compactMap { $0 as? URL }
            .filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted {
                relativePathForTreeHash(file: $0, root: root)
                    < relativePathForTreeHash(file: $1, root: root)
            }
        var treeDigest = SHA256()
        for file in files {
            let relativePath = relativePathForTreeHash(file: file, root: root)
            let relativeData = Data(relativePath.utf8)
            var pathByteCount = UInt32(relativeData.count).bigEndian
            withUnsafeBytes(of: &pathByteCount) {
                treeDigest.update(data: Data($0))
            }
            treeDigest.update(data: relativeData)
            let byteCount = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            var fileByteCount = UInt64(byteCount).bigEndian
            withUnsafeBytes(of: &fileByteCount) {
                treeDigest.update(data: Data($0))
            }
            let fileDigest = SHA256.hash(
                data: try Data(contentsOf: file, options: .mappedIfSafe)
            )
            treeDigest.update(data: Data(fileDigest))
        }
        return treeDigest.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    fileprivate static func relativePathForTreeHash(
        file: URL,
        root: URL
    ) -> String {
        let canonicalFile = file.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        return canonicalFile.path.replacingOccurrences(
            of: canonicalRoot.path + "/",
            with: ""
        )
    }

    private static func processCPUTimeMS() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "getrusage could not read process CPU time"
            )
        }
        let user = Double(usage.ru_utime.tv_sec) * 1_000
            + Double(usage.ru_utime.tv_usec) / 1_000
        let system = Double(usage.ru_stime.tv_sec) * 1_000
            + Double(usage.ru_stime.tv_usec) / 1_000
        return user + system
    }

    private static func currentResidentMemoryMiB() throws -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw EnterprisePerformanceBenchmarkError.invalidResult(
                "task_info could not read resident memory"
            )
        }
        return Double(info.resident_size) / 1_048_576
    }
}

@Test func enterpriseBenchmarkTreeHashCanonicalizesTemporaryDirectoryAliases() throws {
    let identifier = "clipease-fixture-\(UUID().uuidString)"
    let physicalRoot = URL(
        fileURLWithPath: "/private/tmp/\(identifier)/S1K",
        isDirectory: true
    )
    let logicalRoot = URL(
        fileURLWithPath: "/tmp/\(identifier)/S1K",
        isDirectory: true
    )
    let physicalFile = physicalRoot.appendingPathComponent("items.jsonl")
    try FileManager.default.createDirectory(
        at: physicalRoot,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(
            at: physicalRoot
                .deletingLastPathComponent()
        )
    }
    try Data("ClipEase fixture\n".utf8).write(to: physicalFile, options: .atomic)

    #expect(
        EnterprisePerformanceBenchmarkContext.relativePathForTreeHash(
            file: physicalFile,
            root: logicalRoot
        ) == "items.jsonl"
    )
}

@Test func enterpriseBenchmarkBulkLoaderCreatesSearchableVersionNeutralDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "clipease-enterprise-bulk-loader-\(UUID().uuidString)",
            isDirectory: true
        )
    let databaseURL = directory.appendingPathComponent("fixture.sqlite")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = EnterpriseBenchmarkItemRecord(
        id: UUID(),
        type: "text",
        plainText: "ordinary fixture row",
        sourceBundleID: "com.clipease.fixture.first",
        createdAt: 1_700_000_000,
        updatedAt: 1_700_000_000,
        isPinned: false,
        searchToken: "token-001"
    )
    let second = EnterpriseBenchmarkItemRecord(
        id: UUID(),
        type: "file",
        plainText: "unique searchable fixture row",
        sourceBundleID: "com.clipease.fixture.zz",
        createdAt: 1_700_000_001,
        updatedAt: 1_700_000_001,
        isPinned: true,
        searchToken: "token-002"
    )
    let image = EnterpriseBenchmarkItemRecord(
        id: UUID(),
        type: "image",
        plainText: "image fixture row",
        sourceBundleID: "com.clipease.fixture.image",
        createdAt: 1_700_000_002,
        updatedAt: 1_700_000_002,
        isPinned: false,
        searchToken: "token-003"
    )
    let richText = EnterpriseBenchmarkItemRecord(
        id: UUID(),
        type: "richText",
        plainText: "rich text fixture row",
        sourceBundleID: "com.clipease.fixture.richtext",
        createdAt: 1_700_000_003,
        updatedAt: 1_700_000_003,
        isPinned: false,
        searchToken: "token-004"
    )

    try EnterpriseBenchmarkFixtureDatabaseLoader.load(
        records: [first, second, image, richText],
        fixtureID: "pathneedle",
        databaseURL: databaseURL
    )

    let database = try SQLiteConnection(url: databaseURL)
    defer { database.close() }
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_items") == 4)
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_items_fts") == 4)
    #expect(try database.queryInt("SELECT COUNT(*) FROM item_assets") == 2)
    #expect(try database.queryInt("SELECT COUNT(*) FROM clipboard_item_files") == 1)
    let indexedSearchText = try database.query(
        "SELECT search_text FROM clipboard_items_fts WHERE item_id = ?",
        values: [.text(second.id.uuidString)]
    ).first?.requiredText("search_text")

    let store = SQLiteClipboardStore(databaseURL: databaseURL)
    let itemsByID = Dictionary(
        uniqueKeysWithValues: try store.loadItems(limit: 10, offset: 0)
            .map { ($0.id, $0) }
    )
    let results = try store.searchItems(
        ClipboardSearchQuery(text: "unique searchable", limit: 10)
    )
    let fileNameToken = second.id.uuidString.split(separator: "-")[0]
    let fileNameResults = try store.searchItems(
        ClipboardSearchQuery(text: String(fileNameToken), limit: 10)
    )
    let filePathResults = try store.searchItems(
        ClipboardSearchQuery(text: "pathneedle", limit: 10)
    )
    let sourceAppNameOnlyResults = try store.searchItems(
        ClipboardSearchQuery(text: "zz", limit: 10)
    )
    #expect(results.map(\.id) == [second.id])
    #expect(fileNameResults.map(\.id) == [second.id])
    #expect(filePathResults.map(\.id) == [second.id])
    #expect(sourceAppNameOnlyResults.isEmpty)
    #expect(indexedSearchText == itemsByID[second.id]?.cardSearchText)
    #expect(
        itemsByID[second.id]?.fileReferences.first?.path
            == "/synthetic/pathneedle/\(second.id.uuidString).txt"
    )
    #expect(itemsByID[second.id]?.fileReferences.first?.pathStatus == .available)
    #expect(itemsByID[image.id]?.imageFileName == "\(image.id.uuidString).png")
    #expect(itemsByID[image.id]?.imageWidth == 640)
    #expect(itemsByID[image.id]?.imageHeight == 360)
    #expect(itemsByID[richText.id]?.type == .text)
    #expect(itemsByID[richText.id]?.richTextFileName == "\(richText.id.uuidString).rtf")
}
