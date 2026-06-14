import XCTest
import Foundation
@testable import SQLCore

final class SQLLiteralScannerTests: XCTestCase {

    /// (location, length, isComment) for each range, in order.
    private func scan(_ s: String) -> [(Int, Int, Bool)] {
        SQLLiteralScanner.literalAndCommentRanges(in: s).map {
            ($0.range.location, $0.range.length, $0.isComment)
        }
    }

    private func assertEqual(_ a: [(Int, Int, Bool)], _ b: [(Int, Int, Bool)],
                             file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, "count", file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertTrue(x == y, "\(x) != \(y)", file: file, line: line)
        }
    }

    func testSingleQuotedString() {
        assertEqual(scan("SELECT 'a;b'"), [(7, 5, false)])
    }

    func testEscapedQuote() {
        // "'it''s'" is one string of length 7.
        assertEqual(scan("'it''s'"), [(0, 7, false)])
    }

    func testTwoStrings() {
        // "'a' 'b'" → two strings.
        assertEqual(scan("'a' 'b'"), [(0, 3, false), (4, 3, false)])
    }

    func testLineComment() {
        assertEqual(scan("x -- c\ny"), [(2, 4, true)])
    }

    func testBlockComment() {
        assertEqual(scan("a /* b */ c"), [(2, 7, true)])
    }

    func testDollarQuote() {
        assertEqual(scan("$$ a; b $$"), [(0, 10, false)])
    }

    func testTaggedDollarQuote() {
        assertEqual(scan("$x$ a $x$"), [(0, 9, false)])
    }

    func testDashDashInsideStringIsNotAComment() {
        assertEqual(scan("'-- not'"), [(0, 8, false)])
    }

    func testQuoteInsideCommentIsNotAString() {
        assertEqual(scan("-- it's"), [(0, 7, true)])
    }

    func testMixed() {
        // string, then line comment
        assertEqual(scan("WHERE x = 'a' -- note"),
                    [(10, 3, false), (14, 7, true)])
    }

    func testNoLiterals() {
        assertEqual(scan("SELECT * FROM t WHERE id = 5"), [])
    }

    func testUnterminatedStringRunsToEnd() {
        // A still-being-typed string highlights to the end of input.
        assertEqual(scan("SELECT 'abc"), [(7, 4, false)])
    }
}
