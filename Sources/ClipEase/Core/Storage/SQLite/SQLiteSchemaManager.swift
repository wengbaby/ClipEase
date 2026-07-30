import Foundation

struct SQLiteSchemaManager {
    let currentSchemaVersion: Int

    func createSchema(in database: SQLiteDatabase) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_versions (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                plain_text TEXT NOT NULL DEFAULT '',
                url TEXT,
                link_title TEXT,
                link_subtitle TEXT,
                source_app_name TEXT NOT NULL DEFAULT '',
                source_bundle_id TEXT,
                source_icon_name TEXT NOT NULL DEFAULT '',
                source_icon_file_name TEXT,
                header_color TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_used_at REAL,
                pinned_at REAL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                last_edited_at REAL,
                group_sort_order INTEGER,
                content_hash TEXT,
                content_digest BLOB,
                digest_version INTEGER
            )
            """)
        try addColumnIfNeeded(
            "clipboard_items",
            column: "content_digest",
            definition: "BLOB",
            in: database
        )
        try addColumnIfNeeded(
            "clipboard_items",
            column: "digest_version",
            definition: "INTEGER",
            in: database
        )

        try database.execute("""
            CREATE TABLE IF NOT EXISTS item_assets (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                file_name TEXT NOT NULL,
                original_file_name TEXT,
                width INTEGER,
                height INTEGER,
                byte_size INTEGER,
                created_at REAL NOT NULL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_item_files (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL,
                display_order INTEGER NOT NULL DEFAULT 0,
                file_path TEXT NOT NULL,
                file_name TEXT NOT NULL,
                file_extension TEXT,
                uti_or_content_type TEXT,
                byte_size INTEGER,
                modified_at REAL,
                is_directory INTEGER NOT NULL DEFAULT 0,
                is_alias INTEGER NOT NULL DEFAULT 0,
                path_status TEXT NOT NULL DEFAULT 'unknown',
                last_checked_at REAL,
                created_at REAL NOT NULL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS group_items (
                id TEXT PRIMARY KEY,
                group_id TEXT NOT NULL,
                item_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(item_id),
                FOREIGN KEY(group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS item_ocr_results (
                item_id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                recognized_text TEXT NOT NULL DEFAULT '',
                emails TEXT NOT NULL DEFAULT '',
                phone_numbers TEXT NOT NULL DEFAULT '',
                urls TEXT NOT NULL DEFAULT '',
                text_regions TEXT NOT NULL DEFAULT '',
                updated_at REAL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            )
            """)
        try addColumnIfNeeded("item_ocr_results", column: "text_regions", definition: "TEXT NOT NULL DEFAULT ''", in: database)

        try database.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(
                item_id UNINDEXED,
                search_text,
                tokenize='unicode61'
            )
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_search_index_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(created_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_type_created_at ON clipboard_items(type, created_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_source_app ON clipboard_items(source_app_name)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_source_bundle ON clipboard_items(source_bundle_id)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_items_pinned ON clipboard_items(is_pinned, pinned_at DESC)"
        )
        // `is_deleted` has very low selectivity and this full index can win over
        // the measured active-row duplicate indexes on the production-width
        // table. Remove it for both fresh databases and upgraded installations.
        try database.execute("DROP INDEX IF EXISTS idx_clipboard_items_deleted")
        // Superseded by the active-row composite index below. Keeping both
        // gives SQLite two competing equality plans and can select the legacy
        // index that does not cover the actual duplicate-lookup predicate.
        try database.execute("DROP INDEX IF EXISTS idx_clipboard_items_content_hash")
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_content_digest
            ON clipboard_items(digest_version, content_digest, source_bundle_id)
            WHERE is_deleted = 0
            """
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_content_hash_active
            ON clipboard_items(content_hash, source_bundle_id)
            WHERE is_deleted = 0
            """
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_assets_item_id ON item_assets(item_id)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_assets_type ON item_assets(asset_type)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_item_files_item_id ON clipboard_item_files(item_id, display_order)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_group_items_group_id ON group_items(group_id, sort_order)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_item_ocr_results_status ON item_ocr_results(status)"
        )
    }

    func recordSchemaVersion(in database: SQLiteDatabase) throws {
        try database.execute("PRAGMA user_version = \(currentSchemaVersion)")
        try database.execute(
            "INSERT OR IGNORE INTO schema_versions (version, applied_at) VALUES (?, ?)",
            values: [.int(currentSchemaVersion), .double(Date().timeIntervalSince1970)]
        )
    }

    private func addColumnIfNeeded(
        _ table: String,
        column: String,
        definition: String,
        in database: SQLiteDatabase
    ) throws {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let rows = try database.query("PRAGMA table_info('\(escapedTable)')")
        guard !rows.contains(where: { $0.requiredText("name") == column }) else {
            return
        }

        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
