import FoundationModels
import ScreenshotKit

/// Asks the on-device Apple Intelligence model to pick a built-in category. Nothing leaves the device.
/// Returns `nil` when this screenshot can't be judged; throws when the model can't answer right now.
@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsClassifier: ScreenshotClassifier {
    public enum Unavailable: Error {
        case model(SystemLanguageModel.Availability.UnavailableReason)
    }

    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict? {
        if case let .unavailable(reason) = model.availability {
            throw Unavailable.model(reason)
        }
        let session = LanguageModelSession(model: model, instructions: LLMCategoryPrompt.instructions(excluding: input.excluded))
        do {
            let response = try await session.respond(
                to: LLMCategoryPrompt.prompt(for: input.text),
                schema: Self.answerSchema(excluding: input.excluded),
                options: Self.greedy
            )
            return try LLMCategoryPrompt.verdict(
                category: response.content.value(String.self, forProperty: "category"),
                certainty: response.content.value(String.self, forProperty: "certainty")
            )
        } catch let error as LanguageModelSession.GenerationError where Self.isPerInput(error) {
            return nil
        }
    }

    // The iOS 27 SDK (Swift 6.4) renames `sampling:` to `samplingMode:`, back-deployed to iOS 26; older SDKs only have `sampling:`.
    #if compiler(>=6.4)
    private static let greedy = GenerationOptions(samplingMode: .greedy)
    #else
    private static let greedy = GenerationOptions(sampling: .greedy)
    #endif

    /// `{ category: one of the offered keys or "none", certainty: high | medium | low }`
    private static func answerSchema(excluding excluded: Set<ClassificationTarget>) throws -> GenerationSchema {
        let answer = DynamicGenerationSchema(name: "CategoryAnswer", properties: [
            .init(name: "category", schema: DynamicGenerationSchema(
                name: "Category",
                anyOf: LLMCategoryPrompt.choices(excluding: excluded)
            )),
            .init(name: "certainty", schema: DynamicGenerationSchema(
                name: "Certainty",
                anyOf: LLMCategoryPrompt.Certainty.allCases.map(\.rawValue)
            )),
        ])
        return try GenerationSchema(root: answer, dependencies: [])
    }

    /// Errors that would happen again for the same text. Everything else (busy, assets missing) is worth retrying.
    private static func isPerInput(_ error: LanguageModelSession.GenerationError) -> Bool {
        switch error {
        case .exceededContextWindowSize, .guardrailViolation, .unsupportedGuide, .unsupportedLanguageOrLocale,
             .decodingFailure, .refusal:
            return true
        case .assetsUnavailable, .rateLimited, .concurrentRequests:
            return false
        @unknown default:
            return false
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
public extension ClassificationPipeline {
    /// The refinement pass for screenshots the rules left in 未分類.
    static let appleIntelligence = ClassificationPipeline(layers: [
        Layer(FoundationModelsClassifier(), threshold: 0.6),
    ])
}
