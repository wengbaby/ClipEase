import Foundation

struct SQLiteAssetRow {
    let type: String
    let fileName: String
    let width: Int?
    let height: Int?
}

struct SQLiteOCRResultRow {
    let status: ClipboardOCRStatus
    let text: String
    let emails: [String]
    let phoneNumbers: [String]
    let urls: [String]
    let textRegions: [ClipboardOCRTextRegion]
    let updatedAt: Date?
}

struct SQLiteGroupItemRow {
    let groupID: UUID
    let createdAt: Date
    let sortOrder: Int
}

enum SQLiteRowMapper {
    static func makeItem(
        from row: SQLiteRow,
        id: UUID,
        assets: [SQLiteAssetRow],
        fileReferences: [ClipboardFileReference],
        groupInfo: SQLiteGroupItemRow?,
        ocrResult: SQLiteOCRResultRow?
    ) -> ClipboardItem {
        let imageAsset = assets.first { $0.type == "image" }
        let richTextAsset = assets.first { $0.type == "rich_text" }

        return ClipboardItem(
            id: id,
            type: ClipboardItemType(rawValue: row.requiredText("type")) ?? .text,
            text: row.requiredText("plain_text"),
            url: row.optionalText("url").flatMap(URL.init(string:)),
            linkTitle: row.optionalText("link_title"),
            linkSubtitle: row.optionalText("link_subtitle"),
            imageFileName: imageAsset?.fileName,
            imageWidth: imageAsset?.width,
            imageHeight: imageAsset?.height,
            imageHash: row.optionalText("content_hash"),
            richTextFileName: richTextAsset?.fileName,
            fileReferences: fileReferences,
            createdAt: Date(timeIntervalSince1970: row.requiredDouble("created_at")),
            sourceAppName: row.requiredText("source_app_name"),
            sourceBundleID: row.optionalText("source_bundle_id"),
            iconName: row.requiredText("source_icon_name"),
            iconFileName: row.optionalText("source_icon_file_name"),
            headerColorHex: row.requiredText("header_color"),
            isPinned: row.requiredBool("is_pinned"),
            pinnedAt: row.optionalDouble("pinned_at").map(Date.init(timeIntervalSince1970:)),
            groupID: groupInfo?.groupID,
            groupedAt: groupInfo?.createdAt,
            ocrStatus: ocrResult?.status ?? .none,
            ocrText: ocrResult?.text ?? "",
            ocrEmails: ocrResult?.emails ?? [],
            ocrPhoneNumbers: ocrResult?.phoneNumbers ?? [],
            ocrURLs: ocrResult?.urls ?? [],
            ocrTextRegions: ocrResult?.textRegions ?? [],
            ocrUpdatedAt: ocrResult?.updatedAt
        )
    }

    static func searchText(for item: ClipboardItem) -> String {
        item.cardSearchText
    }

    static func searchText(from row: SQLiteRow) -> String {
        [
            row.requiredText("plain_text"),
            row.optionalText("url"),
            row.optionalText("link_title"),
            row.optionalText("link_subtitle")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func escapedFTS5Query(_ query: String) -> String {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return "\"\""
        }

        return tokens
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    static func encodeList(_ values: [String]) -> String {
        (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "[]"
    }

    static func decodeList(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return values
    }

    static func encodeRegions(_ regions: [ClipboardOCRTextRegion]) -> String {
        (try? String(data: JSONEncoder().encode(regions), encoding: .utf8)) ?? "[]"
    }

    static func decodeRegions(_ text: String) -> [ClipboardOCRTextRegion] {
        guard let data = text.data(using: .utf8),
              let regions = try? JSONDecoder().decode([ClipboardOCRTextRegion].self, from: data) else {
            return []
        }

        return regions
    }
}
