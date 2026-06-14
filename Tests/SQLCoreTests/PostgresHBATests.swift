import XCTest
@testable import SQLCore

final class PostgresHBATests: XCTestCase {

    func testSuggestsHostLineFromRejection() {
        let msg = #"no pg_hba.conf entry for host "192.168.0.50", user "alice", database "app", no encryption"#
        XCTAssertEqual(PostgresHBA.suggestedLine(fromServerMessage: msg),
                       "host    app    alice    192.168.0.50/32    scram-sha-256")
    }

    func testIPv6UsesSlash128AndStripsZoneIndex() {
        let msg = #"no pg_hba.conf entry for host "fe80::1%en0", user "bob", database "db", no encryption"#
        XCTAssertEqual(PostgresHBA.suggestedLine(fromServerMessage: msg),
                       "host    db    bob    fe80::1/128    scram-sha-256")
    }

    func testNonRejectionMessageReturnsNil() {
        XCTAssertNil(PostgresHBA.suggestedLine(fromServerMessage: "password authentication failed for user \"bob\""))
    }

    func testNonIPAddressReturnsNil() {
        let msg = #"no pg_hba.conf entry for host "localhost", user "bob", database "db", no encryption"#
        XCTAssertNil(PostgresHBA.suggestedLine(fromServerMessage: msg))
    }

    func testQuotedValues() {
        XCTAssertEqual(PostgresHBA.quotedValues(in: #"a "one" b "two" c"#), ["one", "two"])
        XCTAssertEqual(PostgresHBA.quotedValues(in: "no quotes here"), [])
    }
}
