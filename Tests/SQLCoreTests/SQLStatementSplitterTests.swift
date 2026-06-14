import XCTest
@testable import SQLCore

final class SQLStatementSplitterTests: XCTestCase {

    func testSimpleMultiStatement() {
        XCTAssertEqual(SQLStatementSplitter.split("SELECT 1; SELECT 2;"),
                       ["SELECT 1;", "SELECT 2;"])
    }

    func testTrailingStatementWithoutSemicolon() {
        XCTAssertEqual(SQLStatementSplitter.split("SELECT 1; SELECT 2"),
                       ["SELECT 1;", "SELECT 2"])
    }

    func testEmptyAndWhitespaceOnly() {
        XCTAssertEqual(SQLStatementSplitter.split("   \n  "), [])
        XCTAssertEqual(SQLStatementSplitter.split(";;;"), [";", ";", ";"])
    }

    func testSemicolonInsideStringLiteralIsNotASplit() {
        XCTAssertEqual(SQLStatementSplitter.split("SELECT ';' AS x;"),
                       ["SELECT ';' AS x;"])
    }

    func testEscapedQuoteInsideString() {
        let sql = "SELECT 'it''s; fine' AS x; SELECT 2;"
        XCTAssertEqual(SQLStatementSplitter.split(sql),
                       ["SELECT 'it''s; fine' AS x;", "SELECT 2;"])
    }

    func testSemicolonInLineCommentIsNotASplit() {
        let sql = "SELECT 1 -- one; two\n; SELECT 2;"
        XCTAssertEqual(SQLStatementSplitter.split(sql),
                       ["SELECT 1 -- one; two\n;", "SELECT 2;"])
    }

    func testSemicolonInBlockCommentIsNotASplit() {
        let sql = "SELECT 1 /* a; b */; SELECT 2;"
        XCTAssertEqual(SQLStatementSplitter.split(sql),
                       ["SELECT 1 /* a; b */;", "SELECT 2;"])
    }

    func testDollarQuotedBodyWithSemicolonsIsOneStatement() {
        let fn = """
        CREATE FUNCTION f() RETURNS int AS $$
        BEGIN
          PERFORM 1; PERFORM 2;
          RETURN 3;
        END;
        $$ LANGUAGE plpgsql;
        """
        let parts = SQLStatementSplitter.split(fn)
        XCTAssertEqual(parts.count, 1, "the whole function body is a single statement")
        XCTAssertTrue(parts[0].contains("RETURN 3;"))
    }

    func testTaggedDollarQuote() {
        let sql = "SELECT $tag$ a; b; $tag$; SELECT 2;"
        XCTAssertEqual(SQLStatementSplitter.split(sql),
                       ["SELECT $tag$ a; b; $tag$;", "SELECT 2;"])
    }

    func testStatementAtCursor() {
        let sql = "SELECT 1; SELECT 2; SELECT 3;"
        // Offsets: "SELECT 1;" is 0..<9, " SELECT 2;" 9..<19, " SELECT 3;" 19..<29
        XCTAssertEqual(SQLStatementSplitter.statement(atOffset: 3, in: sql), "SELECT 1;")
        XCTAssertEqual(SQLStatementSplitter.statement(atOffset: 14, in: sql), "SELECT 2;")
        XCTAssertEqual(SQLStatementSplitter.statement(atOffset: 25, in: sql), "SELECT 3;")
    }

    func testStatementAtCursorAtEnd() {
        let sql = "SELECT 1; SELECT 2"
        XCTAssertEqual(SQLStatementSplitter.statement(atOffset: sql.count, in: sql), "SELECT 2")
    }
}
