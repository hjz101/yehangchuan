import XCTest
@testable import LegadoCore

final class RegexEvaluatorTests: XCTestCase {
    func testReplaceFirstWithoutMatchKeepsInput() throws {
        let evaluator = RegexEvaluator()
        let input = "第一章 起点"
        XCTAssertEqual(
            try evaluator.replacing(pattern: "不存在", in: input, with: "替换", firstOnly: true),
            input
        )
    }

    func testReplaceFirstWithMalformedPatternThrows() {
        let evaluator = RegexEvaluator()
        XCTAssertThrowsError(
            try evaluator.replacing(pattern: "([", in: "文本", with: "替换", firstOnly: true)
        ) { error in
            guard case RuleEngineError.malformedRule = error else {
                return XCTFail("期望 malformedRule，实际为 \(error)")
            }
        }
    }
}
