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

    func testMatchLimitAllowsExactlyMaximumMatches() throws {
        let evaluator = RegexEvaluator(limits: RegexLimits(maximumMatches: 3))
        XCTAssertEqual(try evaluator.captureGroups(pattern: "a", input: "aaa").count, 3)
        XCTAssertThrowsError(try evaluator.captureGroups(pattern: "a", input: "aaaa")) { error in
            guard case RuleEngineError.resourceLimit = error else {
                return XCTFail("期望 resourceLimit，实际为 \(error)")
            }
        }
    }
}

