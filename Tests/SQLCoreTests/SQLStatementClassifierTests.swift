import XCTest
@testable import SQLCore

final class SQLStatementClassifierTests: XCTestCase {

    private func classify(_ s: String) -> SQLStatementInfo { SQLStatementClassifier.classify(s) }

    func testReads() {
        XCTAssertEqual(classify("SELECT * FROM t").kind, .read)
        XCTAssertEqual(classify("  select 1").kind, .read)
        XCTAssertEqual(classify("SHOW server_encoding").kind, .read)
        XCTAssertEqual(classify("VALUES (1),(2)").kind, .read)
        XCTAssertEqual(classify("PRAGMA table_info('t')").kind, .read)
    }

    func testWrites() {
        XCTAssertEqual(classify("INSERT INTO t VALUES (1)").kind, .write)
        XCTAssertEqual(classify("update t set x = 1 where id = 2").kind, .write)
        XCTAssertEqual(classify("CREATE TABLE t (id int)").kind, .write)
        XCTAssertEqual(classify("ALTER TABLE t ADD COLUMN c int").kind, .write)
        XCTAssertEqual(classify("GRANT SELECT ON t TO bob").kind, .write)
    }

    func testNeutral() {
        XCTAssertEqual(classify("BEGIN").kind, .neutral)
        XCTAssertEqual(classify("COMMIT").kind, .neutral)
        XCTAssertEqual(classify("ROLLBACK").kind, .neutral)
        XCTAssertEqual(classify("SET search_path TO public").kind, .neutral)
        // Unrecognised → neutral (never block a read we don't understand).
        XCTAssertEqual(classify("FROBNICATE foo").kind, .neutral)
    }

    func testLeadingKeywordUppercased() {
        XCTAssertEqual(classify("  -- c\n select 1").leadingKeyword, "SELECT")
        XCTAssertEqual(classify("/* x */ DrOp TABLE t").leadingKeyword, "DROP")
    }

    func testDestructiveDropAndTruncate() {
        XCTAssertTrue(classify("DROP TABLE t").isDestructive)
        XCTAssertTrue(classify("truncate t").isDestructive)
        XCTAssertTrue(classify("DROP TABLE t").kind == .write)
    }

    func testDeleteUpdateWithoutWhereIsDestructive() {
        XCTAssertTrue(classify("DELETE FROM t").isDestructive)
        XCTAssertTrue(classify("UPDATE t SET x = 1").isDestructive)
    }

    func testDeleteUpdateWithWhereIsNotDestructive() {
        XCTAssertFalse(classify("DELETE FROM t WHERE id = 1").isDestructive)
        XCTAssertFalse(classify("UPDATE t SET x = 1 WHERE id = 2").isDestructive)
    }

    func testWhereInsideStringDoesNotCount() {
        // No real WHERE clause → still destructive even though the literal says "where".
        XCTAssertTrue(classify("UPDATE t SET note = 'no where here'").isDestructive)
    }

    func testCommentedDropIsNotClassifiedAsDrop() {
        // Leading keyword comes from real code, not the comment.
        let info = classify("-- DROP TABLE t\nSELECT 1")
        XCTAssertEqual(info.leadingKeyword, "SELECT")
        XCTAssertFalse(info.isDestructive)
    }

    func testWithCTE() {
        XCTAssertEqual(classify("WITH x AS (SELECT 1) SELECT * FROM x").kind, .read)
        XCTAssertEqual(classify("WITH x AS (SELECT 1) DELETE FROM t WHERE id IN (SELECT 1)").kind, .write)
    }

    func testExplain() {
        XCTAssertEqual(classify("EXPLAIN SELECT 1").kind, .read)
        // EXPLAIN ANALYZE actually executes — treat as a write.
        XCTAssertEqual(classify("EXPLAIN ANALYZE UPDATE t SET x = 1").kind, .write)
    }

    func testClassifyAllDropsWhitespaceOnlySegments() {
        XCTAssertEqual(SQLStatementClassifier.classifyAll("SELECT 1;   \n  ").map(\.kind), [.read])
        XCTAssertEqual(SQLStatementClassifier.classifyAll("SELECT 1; DELETE FROM t;").map(\.kind),
                       [.read, .write])
    }

    func testBareSemicolonIsNeutral() {
        // A lone ";" is kept (matching the executor's splitter) and is harmless.
        XCTAssertEqual(SQLStatementClassifier.classifyAll("SELECT 1; ; DELETE FROM t WHERE id=1;").map(\.kind),
                       [.read, .neutral, .write])
    }
}
