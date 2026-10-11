import ScreenshotKit
import XCTest

final class LLMCategoryPromptTests: XCTestCase {
    func testChoicesAreEveryBuiltInPlusNone() {
        let choices = LLMCategoryPrompt.choices(excluding: [])
        XCTAssertEqual(choices, BuiltInCategory.allCases.map(\.rawValue) + ["none"])
    }

    func testDeletedBuiltInsAreNeverOffered() {
        let excluded: Set<ClassificationTarget> = [.builtIn(.recipe), .builtIn(.shopping)]
        let choices = LLMCategoryPrompt.choices(excluding: excluded)
        let instructions = LLMCategoryPrompt.instructions(excluding: excluded)

        XCTAssertFalse(choices.contains("recipe"))
        XCTAssertFalse(choices.contains("shopping"))
        XCTAssertTrue(choices.contains("none"))
        XCTAssertFalse(instructions.contains("recipe（"))
        XCTAssertFalse(instructions.contains(BuiltInCategory.shopping.hint))
        XCTAssertTrue(instructions.contains("- receipt（收據）：\(BuiltInCategory.receipt.hint)"))
    }

    func testNoneIsOfferedWithExamples() {
        let instructions = LLMCategoryPrompt.instructions(excluding: [])
        XCTAssertTrue(instructions.contains("- none：天氣"))
    }

    func testPromptCutsLongText() {
        let text = String(repeating: "字", count: LLMCategoryPrompt.maxTextLength + 100)
        let prompt = LLMCategoryPrompt.prompt(for: text)

        XCTAssertEqual(prompt.filter { $0 == "字" }.count, LLMCategoryPrompt.maxTextLength)
        XCTAssertTrue(LLMCategoryPrompt.prompt(for: "短文字").hasSuffix("短文字"))
    }

    func testAnswersBecomeLLMVerdicts() {
        XCTAssertEqual(
            LLMCategoryPrompt.verdict(category: "ticket", certainty: "high"),
            ClassifierVerdict(target: .builtIn(.ticket), confidence: 0.9, source: .llm)
        )
        XCTAssertEqual(LLMCategoryPrompt.verdict(category: "ticket", certainty: "medium")?.confidence, 0.6)
        XCTAssertEqual(LLMCategoryPrompt.verdict(category: "ticket", certainty: "low")?.confidence, 0.3)
    }

    func testNoneAndUnknownAnswersAreNoVerdict() {
        XCTAssertNil(LLMCategoryPrompt.verdict(category: "none", certainty: "high"))
        XCTAssertNil(LLMCategoryPrompt.verdict(category: "sticker", certainty: "high"))
        XCTAssertNil(LLMCategoryPrompt.verdict(category: "ticket", certainty: "sure"))
    }
}
