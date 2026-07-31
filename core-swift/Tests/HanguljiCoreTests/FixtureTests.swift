import XCTest
@testable import HanguljiCore

/// spec/fixtures/*.json conformance 러너 — 모든 플랫폼 포트가 같은 픽스처를 통과해야 한다.
final class FixtureTests: XCTestCase {
    private var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("spec/fixtures")
    }

    func testKanaFixtures() throws {
        struct Case: Decodable { let name: String; let keys: String; let kana: String; let fullyMapped: Bool }
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("kana.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertGreaterThanOrEqual(cases.count, 38)
        for c in cases {
            var composer = HanguljiComposer()
            for ch in c.keys { _ = composer.insert(ch) }
            XCTAssertEqual(composer.markedText, c.kana, c.name)
            XCTAssertEqual(composer.reading != nil, c.fullyMapped, c.name)
        }
    }

    func testCompositionFixtures() throws {
        struct Case: Decodable { let name: String; let keys: String; let syllables: [String] }
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("composition.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for c in cases {
            var composer = JamoComposer()
            for ch in c.keys {
                guard let jamo = Keymap.jamo(for: ch) else { return XCTFail("자모 아님 \(c.name): \(ch)") }
                composer.append(jamo)
            }
            XCTAssertEqual(composer.syllables.map(\.hangul), c.syllables, c.name)
        }
    }
}
