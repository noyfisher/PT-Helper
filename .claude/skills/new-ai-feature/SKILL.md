---
name: new-ai-feature
description: Scaffold a new AI request type across the full stack (server prompt + client enum + ViewModel parsing).
argument-hint: [feature-name]
disable-model-invocation: true
---

# New AI Feature Scaffolder

Add a new AI-powered feature to PT Helper. This requires coordinated changes across 3 layers — this skill ensures nothing is missed.

The feature name is `$ARGUMENTS`. Use it to derive the request type key (snake_case, e.g. `exercise_substitute`).

---

## Checklist

### 1. Server Side — Firebase Cloud Function

**File:** `functions/src/prompts.ts`

Add the system prompt to `SYSTEM_PROMPTS`:
```typescript
feature_name: `Your system prompt here...`,
```

Add model config to `MODEL_CONFIG` (same file):
```typescript
feature_name: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
```

**Existing request types for reference:**
| Key | Model | Max Tokens | Temp | Purpose |
|-----|-------|------------|------|---------|
| `analysis` | claude-haiku-4-5 | 4096 | 0.2 | Primary injury analysis |
| `analysis_verify` | claude-haiku-4-5 | 4096 | 0.2 | Devil's advocate verification |
| `rehab_plan` | claude-haiku-4-5 | 4096 | — | Rehab plan generation |
| `exercise_substitute` | claude-haiku-4-5 | 4096 | — | Exercise swap alternatives |
| `recovery_insights` | claude-haiku-4-5 | 4096 | — | Recovery insight generation |
| `form_analysis` | claude-haiku-4-5 | 4096 | 0.2 | Exercise form feedback |

**Guidelines for the system prompt:**
- Write for a health/fitness context — friendly, educational, not diagnostic
- Include structured output format (JSON preferred) so the client can parse reliably
- Reference the clinical knowledge base pattern if the feature needs medical context
- The request type key in `SYSTEM_PROMPTS` must exactly match the `AIRequestType` raw value on the client

### 2. Client Side — AIRequestType Enum

**File:** `ios/PT-Helper/COIL/Services/ClaudeAPIService.swift` (line ~51)

Add a new case to the `AIRequestType` enum:
```swift
enum AIRequestType: String, Encodable {
    case analysis
    case analysis_verify
    case rehab_plan
    case exercise_substitute
    case recovery_insights
    case form_analysis
    case feature_name  // ← add here
}
```

The raw value (snake_case) must exactly match the key used in `SYSTEM_PROMPTS` on the server.

### 3. ViewModel — Response Parsing

Create a new ViewModel or add to an existing one. Follow the project pattern:

```swift
@MainActor
final class FeatureNameViewModel: ObservableObject {
    @Published var result: FeatureResult?
    @Published var isLoading = false
    @Published var error: String?

    func analyze(userMessage: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await ClaudeAPIService.shared.sendMessage(
                requestType: .feature_name,
                userMessage: userMessage
            )
            // Parse the JSON response
            result = try parseResponse(response)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

**Existing patterns to follow:**
- **Single-call**: `RehabPlanViewModel.swift` — sends one request, parses response
- **Two-call with verification**: `InjuryAnalyzer.swift` — primary call + devil's advocate verification + graceful degradation if call 2 fails
- **With validation pipeline**: `FormFeedbackValidationPipeline.swift` — multi-layer response validation

If the feature needs response validation, add validation layers to `Services/ResponseValidationPipeline.swift` (or create a feature-specific pipeline like `FormFeedbackValidationPipeline.swift`).

### 4. Tests

**Add raw value test** in `ios/PT-Helper/COILTests/Services/ClaudeAPIServiceTests.swift`:
```swift
XCTAssertEqual(AIRequestType.feature_name.rawValue, "feature_name")
```

**Add mock handling** in `ios/PT-Helper/COILTests/Mocks/MockClaudeAPIService.swift`:
- The mock already handles all request types generically via `sendMessage(requestType:userMessage:)` — just verify `lastRequestType` and `allRequestTypes` work with the new case

**Add ViewModel tests** following the `@MainActor` test pattern with `MockClaudeAPIService`.

### 5. Deploy & Test

Before testing the new feature on the simulator:

```bash
cd functions && npm run lint && npm run build && firebase deploy --only functions
```

Then build and run the app to verify the new request type works end-to-end.

---

## Files Modified

| File | Change |
|------|--------|
| `functions/src/prompts.ts` | Add to `SYSTEM_PROMPTS` + `MODEL_CONFIG` |
| `ios/PT-Helper/COIL/Services/ClaudeAPIService.swift` | Add `AIRequestType` case |
| `ios/PT-Helper/COIL/ViewModels/<New>ViewModel.swift` | New or modified ViewModel |
| `ios/PT-Helper/COILTests/Services/ClaudeAPIServiceTests.swift` | Add raw value assertion |
| `ios/PT-Helper/COILTests/ViewModels/<New>ViewModelTests.swift` | New ViewModel tests |
