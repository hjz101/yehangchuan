import XCTest
@testable import LegadoCore

final class JSONPathEvaluatorTests: XCTestCase {
    func testIncompleteRecursiveSelectorThrowsRuleError() {
        let root = JSONValue.object(["id": .number(1)])
        XCTAssertThrowsError(try JSONPathEvaluator().evaluate(path: "$..", in: root)) { error in
            guard case RuleEngineError.malformedRule = error else {
                return XCTFail("期望 malformedRule，实际为 \(error)")
            }
        }
    }

    func testRecursiveSelectorStillWorks() throws {
        let root = JSONValue.object(["book": .object(["id": .number(7)])])
        let values = try JSONPathEvaluator().evaluate(path: "$..id", in: root)
        XCTAssertEqual(values.map(\.stringValue), ["7"])
    }
}
