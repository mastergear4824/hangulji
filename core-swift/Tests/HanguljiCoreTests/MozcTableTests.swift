import XCTest

/// Google 일본어 입력(mozc) 로마자 테이블 automaton 시뮬레이터.
/// 의미론: 키를 pending에 누적 → pending이 어떤 항목의 진접두사면 대기,
/// 정확 일치가 있고 확장 불가면 적용(출력+next를 pending으로), 그 외엔 최장 정확 접두사를 떼어 적용.
final class MozcTableTests: XCTestCase {
    struct Rule { let output: String; let next: String }

    private static var rules: [String: Rule] = [:]
    private static var prefixes: Set<String> = []   // 모든 input의 진접두사 집합

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    override class func setUp() {
        super.setUp()
        let url = repoRoot.appendingPathComponent("windows/hangulji-romaji-table.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("테이블 없음: \(url.path) — gen-mozc-table 먼저 실행")
        }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let input = cols[0]
            rules[input] = Rule(output: cols[1], next: cols.count > 2 ? cols[2] : "")
            var prefix = ""
            for ch in input.dropLast() {
                prefix.append(ch)
                prefixes.insert(prefix)
            }
        }
    }

    private func hasExtension(_ s: String) -> Bool { Self.prefixes.contains(s) }

    private func simulate(_ keys: String) -> String {
        var output = ""
        var pending = ""

        func step() {
            while true {
                if let rule = Self.rules[pending], !hasExtension(pending) {
                    output += rule.output
                    pending = rule.next
                    continue
                }
                if hasExtension(pending) || pending.isEmpty { return }
                // 정확 일치 없음·확장 불가 → 최장 정확 접두사 분리
                var prefix = pending
                while !prefix.isEmpty, Self.rules[prefix] == nil { prefix.removeLast() }
                if prefix.isEmpty {
                    output.append(pending.removeFirst())   // 매핑 불가 키는 그대로
                } else {
                    let rule = Self.rules[prefix]!
                    output += rule.output
                    pending = rule.next + pending.dropFirst(prefix.count)
                }
            }
        }

        for key in keys {
            pending.append(key)
            step()
        }
        // 입력 종료(변환 시점): 남은 pending을 정확 일치로 해소
        while !pending.isEmpty {
            if let rule = Self.rules[pending] {
                output += rule.output
                pending = rule.next
            } else {
                var prefix = pending
                while !prefix.isEmpty, Self.rules[prefix] == nil { prefix.removeLast() }
                if prefix.isEmpty { output.append(pending.removeFirst()) }
                else {
                    let rule = Self.rules[prefix]!
                    output += rule.output
                    pending = rule.next + pending.dropFirst(prefix.count)
                }
            }
        }
        return output
    }

    func testKanaFixturesThroughTable() throws {
        struct Case: Decodable { let name: String; let keys: String; let kana: String; let fullyMapped: Bool }
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent("spec/fixtures/kana.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        var checked = 0
        for c in cases {
            // 테이블은 한글을 출력할 수 없으므로 매핑 불가 케이스는 대상 외 (windows/README에 문서화)
            guard c.fullyMapped else { continue }
            XCTAssertEqual(simulate(c.keys), c.kana, c.name)
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 44)
    }

    func testBatchimReanalysisThroughTable() {
        XCTAssertEqual(simulate("rksl"), "がに")     // 받침 재해석
        XCTAssertEqual(simulate("rksdl"), "がんい")  // 명시적 ㅇ
        XCTAssertEqual(simulate("rks"), "がん")      // 어말 받침
        XCTAssertEqual(simulate("tktvhfh"), "さっぽろ")
        XCTAssertEqual(simulate("dhs"), "おん")      // 온
        XCTAssertEqual(simulate("dh"), "お")         // 대기 중 종료
    }
}
