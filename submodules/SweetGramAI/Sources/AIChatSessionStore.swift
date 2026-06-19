import Foundation
import SweetGramSQLite

// MARK: - Data types

public struct AIChatSession {
    public let id: Int64
    public let peerId: Int64
    public let title: String
    public let messageLimit: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: Int64, peerId: Int64, title: String, messageLimit: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.peerId = peerId
        self.title = title
        self.messageLimit = messageLimit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AIChatMessage {
    public let id: Int64
    public let sessionId: Int64
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: Int64, sessionId: Int64, role: String, content: String, createdAt: Date) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Store

/// SQLite persistence for RAG Q&A sessions.
/// Uses ObjC wrapper (SweetGramSQLite) instead of importing system SQLite3 module
/// to avoid module conflict with sqlcipher on Xcode 26.x SDK.
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
        if SweetGramSQLite.openDatabase(path, db: &db) != 0 {
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
        SweetGramSQLite.exec(db, sql: sql)
    }

    public func createSession(peerId: Int64, title: String, messageLimit: Int) -> AIChatSession? {
        queue.sync {
            guard let db else { return nil }
            let now = Date().timeIntervalSince1970
            let sql = "INSERT INTO ai_sessions (peer_id, title, message_limit, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard SweetGramSQLite.prepare(db, sql: sql, stmt: &stmt) == 0 else { return nil }
            defer { SweetGramSQLite.finalize(stmt) }
            SweetGramSQLite.bindInt64(stmt, index: 1, value: peerId)
            title.withCString { ptr in
                SweetGramSQLite.bindText(stmt, index: 2, value: ptr)
            }
            SweetGramSQLite.bindInt(stmt, index: 3, value: Int32(messageLimit))
            SweetGramSQLite.bindDouble(stmt, index: 4, value: now)
            SweetGramSQLite.bindDouble(stmt, index: 5, value: now)
            guard SweetGramSQLite.step(stmt) == 0x101 /* SQLITE_DONE */ else { return nil }
            let id = SweetGramSQLite.lastInsertRowid(db)
            return AIChatSession(id: id, peerId: peerId, title: title, messageLimit: messageLimit, createdAt: Date(timeIntervalSince1970: now), updatedAt: Date(timeIntervalSince1970: now))
        }
    }

    public func appendMessage(sessionId: Int64, role: String, content: String) {
        queue.sync {
            guard let db else { return }
            let now = Date().timeIntervalSince1970
            let sql = "INSERT INTO ai_messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard SweetGramSQLite.prepare(db, sql: sql, stmt: &stmt) == 0 else { return }
            defer { SweetGramSQLite.finalize(stmt) }
            SweetGramSQLite.bindInt64(stmt, index: 1, value: sessionId)
            role.withCString { ptr in
                SweetGramSQLite.bindText(stmt, index: 2, value: ptr)
            }
            content.withCString { ptr in
                SweetGramSQLite.bindText(stmt, index: 3, value: ptr)
            }
            SweetGramSQLite.bindDouble(stmt, index: 4, value: now)
            SweetGramSQLite.step(stmt)
            let update = "UPDATE ai_sessions SET updated_at = ? WHERE id = ?;"
            var updateStmt: OpaquePointer?
            if SweetGramSQLite.prepare(db, sql: update, stmt: &updateStmt) == 0 {
                SweetGramSQLite.bindDouble(updateStmt, index: 1, value: now)
                SweetGramSQLite.bindInt64(updateStmt, index: 2, value: sessionId)
                SweetGramSQLite.step(updateStmt)
                SweetGramSQLite.finalize(updateStmt)
            }
        }
    }

    public func messages(for sessionId: Int64) -> [AIChatMessage] {
        queue.sync {
            guard let db else { return [] }
            let sql = "SELECT id, session_id, role, content, created_at FROM ai_messages WHERE session_id = ? ORDER BY id ASC;"
            var stmt: OpaquePointer?
            guard SweetGramSQLite.prepare(db, sql: sql, stmt: &stmt) == 0 else { return [] }
            defer { SweetGramSQLite.finalize(stmt) }
            SweetGramSQLite.bindInt64(stmt, index: 1, value: sessionId)
            var result: [AIChatMessage] = []
            while SweetGramSQLite.step(stmt) == 0x101 /* SQLITE_ROW */ {
                let id = SweetGramSQLite.columnInt64(stmt, index: 0)
                let sid = SweetGramSQLite.columnInt64(stmt, index: 1)
                let role = String(cString: SweetGramSQLite.columnText(stmt, index: 2))
                let content = String(cString: SweetGramSQLite.columnText(stmt, index: 3))
                let ts = SweetGramSQLite.columnDouble(stmt, index: 4)
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
            guard SweetGramSQLite.prepare(db, sql: sql, stmt: &stmt) == 0 else { return [] }
            defer { SweetGramSQLite.finalize(stmt) }
            SweetGramSQLite.bindInt64(stmt, index: 1, value: peerId)
            var result: [AIChatSession] = []
            while SweetGramSQLite.step(stmt) == 0x101 /* SQLITE_ROW */ {
                result.append(AIChatSession(
                    id: SweetGramSQLite.columnInt64(stmt, index: 0),
                    peerId: SweetGramSQLite.columnInt64(stmt, index: 1),
                    title: String(cString: SweetGramSQLite.columnText(stmt, index: 2)),
                    messageLimit: Int(SweetGramSQLite.columnInt(stmt, index: 3)),
                    createdAt: Date(timeIntervalSince1970: SweetGramSQLite.columnDouble(stmt, index: 4)),
                    updatedAt: Date(timeIntervalSince1970: SweetGramSQLite.columnDouble(stmt, index: 5))
                ))
            }
            return result
        }
    }
}
