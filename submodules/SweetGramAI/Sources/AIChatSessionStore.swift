import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct AIChatSession: Equatable, Identifiable {
    public let id: Int64
    public let peerId: Int64
    public let title: String
    public let messageLimit: Int
    public let createdAt: Date
    public let updatedAt: Date
}

public struct AIChatMessage: Equatable, Identifiable {
    public let id: Int64
    public let sessionId: Int64
    public let role: String
    public let content: String
    public let createdAt: Date
}

/// SQLite persistence for RAG Q&A sessions.
public final class AIChatSessionStore {
    public static let shared = AIChatSessionStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sweetgram.ai-sessions")

    private init() {
        queue.sync {
            openDatabase()
            createTables()
        }
    }

    private func databaseURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("sweetgram", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai_sessions.sqlite")
    }

    private func openDatabase() {
        let path = databaseURL().path
        if sqlite3_open(path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func createTables() {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS ai_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            peer_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            message_limit INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ai_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES ai_sessions(id)
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    public func createSession(peerId: Int64, title: String, messageLimit: Int) -> AIChatSession? {
        queue.sync {
            guard let db else { return nil }
            let now = Date().timeIntervalSince1970
            let sql = "INSERT INTO ai_sessions (peer_id, title, message_limit, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, peerId)
            sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(messageLimit))
            sqlite3_bind_double(stmt, 4, now)
            sqlite3_bind_double(stmt, 5, now)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            let id = sqlite3_last_insert_rowid(db)
            return AIChatSession(id: id, peerId: peerId, title: title, messageLimit: messageLimit, createdAt: Date(timeIntervalSince1970: now), updatedAt: Date(timeIntervalSince1970: now))
        }
    }

    public func appendMessage(sessionId: Int64, role: String, content: String) {
        queue.sync {
            guard let db else { return }
            let now = Date().timeIntervalSince1970
            let sql = "INSERT INTO ai_messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sessionId)
            sqlite3_bind_text(stmt, 2, role, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, content, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, now)
            sqlite3_step(stmt)
            let update = "UPDATE ai_sessions SET updated_at = ? WHERE id = ?;"
            var updateStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, update, -1, &updateStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(updateStmt, 1, now)
                sqlite3_bind_int64(updateStmt, 2, sessionId)
                sqlite3_step(updateStmt)
                sqlite3_finalize(updateStmt)
            }
        }
    }

    public func messages(for sessionId: Int64) -> [AIChatMessage] {
        queue.sync {
            guard let db else { return [] }
            let sql = "SELECT id, session_id, role, content, created_at FROM ai_messages WHERE session_id = ? ORDER BY id ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sessionId)
            var result: [AIChatMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let sid = sqlite3_column_int64(stmt, 1)
                let role = String(cString: sqlite3_column_text(stmt, 2))
                let content = String(cString: sqlite3_column_text(stmt, 3))
                let ts = sqlite3_column_double(stmt, 4)
                result.append(AIChatMessage(id: id, sessionId: sid, role: role, content: content, createdAt: Date(timeIntervalSince1970: ts)))
            }
            return result
        }
    }

    public func sessions(for peerId: Int64) -> [AIChatSession] {
        queue.sync {
            guard let db else { return [] }
            let sql = "SELECT id, peer_id, title, message_limit, created_at, updated_at FROM ai_sessions WHERE peer_id = ? ORDER BY updated_at DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, peerId)
            var result: [AIChatSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(AIChatSession(
                    id: sqlite3_column_int64(stmt, 0),
                    peerId: sqlite3_column_int64(stmt, 1),
                    title: String(cString: sqlite3_column_text(stmt, 2)),
                    messageLimit: Int(sqlite3_column_int(stmt, 3)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                ))
            }
            return result
        }
    }
}
