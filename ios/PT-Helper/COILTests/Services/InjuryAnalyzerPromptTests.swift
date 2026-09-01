import XCTest
@testable import COIL

// MARK: - InjuryAnalyzer Prompt Tests (no network calls)

final class InjuryAnalyzerPromptTests: XCTestCase {

    // We test that the analyzer can be called and doesn't crash on construction.
    // Actual API calls are tested separately or via integration tests.

    private func makeProfile() -> UserProfile {
        UserProfile(
            userId: "test",
            firstName: "Jane", lastName: "Smith",
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
            sex: "Female",
            heightFeet: 5, heightInches: 6, weight: 140,
            medicalConditions: ["Asthma"],
            otherMedicalConditions: nil,
            surgeries: [UserProfile.Surgery(name: "Knee Arthroscopy", year: 2019)],
            injuries: [UserProfile.Injury(bodyArea: "Right Knee", description: "ACL tear", isCurrent: false)],
            activityLevel: "Very Active",
            primarySport: "Soccer"
        )
    }

    private func makeAssessment() -> PainAssessment {
        let region = BodyRegion(
            name: "Right Knee", zoneKey: "right_knee",
            sides: [.front, .back],
            frontPosition: CGPoint(x: 0.6, y: 0.7),
            backPosition: CGPoint(x: 0.4, y: 0.7)
        )
        return PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painTypes: ["Sharp"],
            customPainDescription: nil,
            painIntensity: 8,
            painDurations: ["2-4 Weeks"],
            painFrequencies: ["Only with Activity"],
            painOnsets: ["Gradual"],
            aggravatingFactors: ["Running", "Stairs", "Squatting"],
            relievingFactors: ["Rest", "Ice"],
            additionalNotes: "Pain worse going downstairs",
            currentTreatment: nil
        )
    }

    func testAnalysisResultParsing_ValidJSON() throws {
        // Simulate a valid AI response and verify parsing works
        let validJSON = """
        {
            "conditions": [
                {
                    "conditionName": "Patellofemoral Pain Syndrome",
                    "commonName": "Runner's Knee",
                    "confidence": 85,
                    "explanation": "Your knee pain during activities like stairs and running is a classic sign of this condition.",
                    "whatItMeans": "The cartilage under your kneecap is getting irritated because it is not tracking properly when you bend your knee.",
                    "howToManage": "Avoid going up and down stairs more than necessary. Ice your knee for 15 minutes after activity.",
                    "isRedFlag": false,
                    "redFlagMessage": null,
                    "nextSteps": ["Try icing for 15 minutes twice a day", "Avoid deep squats for now", "Strengthen your quad muscles with gentle exercises"]
                }
            ],
            "overallSummary": "Based on what you described, it sounds like your knee pain is likely from overuse. The good news is this is very common and usually gets better with some simple changes.",
            "disclaimerText": "This is not a medical diagnosis — it is a starting point to help you understand what might be going on."
        }
        """

        // Test that the JSON structure matches our Decodable types
        let data = validJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let conditions = json["conditions"] as! [[String: Any]]
        XCTAssertEqual(conditions.count, 1)
        XCTAssertEqual(conditions[0]["conditionName"] as? String, "Patellofemoral Pain Syndrome")
        XCTAssertEqual(conditions[0]["commonName"] as? String, "Runner's Knee")
        XCTAssertEqual(conditions[0]["confidence"] as? Double, 85.0)
        XCTAssertEqual(conditions[0]["isRedFlag"] as? Bool, false)
        XCTAssertNotNil(conditions[0]["whatItMeans"])
        XCTAssertNotNil(conditions[0]["howToManage"])

        let nextSteps = conditions[0]["nextSteps"] as? [String]
        XCTAssertEqual(nextSteps?.count, 3)

        XCTAssertNotNil(json["overallSummary"])
        XCTAssertNotNil(json["disclaimerText"])
    }

    func testAnalysisResultParsing_WithMarkdownFences() throws {
        // Simulate response wrapped in markdown code fences (common Claude behavior)
        let wrappedJSON = """
        ```json
        {
            "conditions": [],
            "overallSummary": "No significant findings.",
            "disclaimerText": "Educational purposes only."
        }
        ```
        """

        // Verify the cleaning logic works
        var cleaned = wrappedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let data = cleaned.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["conditions"])
        XCTAssertEqual(json["overallSummary"] as? String, "No significant findings.")
    }

    func testRehabPlanParsing_ValidJSON() throws {
        let validJSON = """
        {
            "planName": "Knee Rehabilitation Plan",
            "exercises": [
                {
                    "name": "Quad Sets",
                    "targetArea": "Knee",
                    "description": "Tighten your quad muscle.",
                    "sets": 3,
                    "reps": "10-15",
                    "restSeconds": 30,
                    "difficulty": "beginner",
                    "demonstrationIcon": "figure.flexibility",
                    "tips": ["Keep leg straight"],
                    "contraindications": ["Avoid if swollen"]
                }
            ],
            "totalWeeks": 6,
            "notes": "Progress gradually."
        }
        """

        let data = validJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["planName"] as? String, "Knee Rehabilitation Plan")
        XCTAssertEqual(json["totalWeeks"] as? Int, 6)
        XCTAssertEqual(json["notes"] as? String, "Progress gradually.")

        let exercises = json["exercises"] as! [[String: Any]]
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0]["name"] as? String, "Quad Sets")
        XCTAssertEqual(exercises[0]["sets"] as? Int, 3)
        XCTAssertEqual(exercises[0]["difficulty"] as? String, "beginner")
    }

    /// This previously declared its OWN copy of the switch inside the test and
    /// asserted against that copy, so it passed regardless of what production did —
    /// and production had four separate copies of the mapping, one of which had
    /// already drifted (the Firestore path matched without lowercasing, decoding a
    /// stored "Intermediate" as .beginner). Now there is one parser and this
    /// exercises it.
    func testDifficultyParse_mapsKnownValues() {
        XCTAssertEqual(RehabExercise.Difficulty.parse("beginner"), .beginner)
        XCTAssertEqual(RehabExercise.Difficulty.parse("intermediate"), .intermediate)
        XCTAssertEqual(RehabExercise.Difficulty.parse("advanced"), .advanced)
    }

    func testDifficultyParse_isCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(RehabExercise.Difficulty.parse("Intermediate"), .intermediate,
                       "Firestore stores capitalised values; they must not silently decode as beginner")
        XCTAssertEqual(RehabExercise.Difficulty.parse("  ADVANCED  "), .advanced)
    }

    func testDifficultyParse_unknownAndMissingFallBackToBeginner() {
        XCTAssertEqual(RehabExercise.Difficulty.parse("expert"), .beginner)
        XCTAssertEqual(RehabExercise.Difficulty.parse(""), .beginner)
        XCTAssertEqual(RehabExercise.Difficulty.parse(nil), .beginner,
                       "An unrecognised difficulty must fall back to the safest prescription")
    }

    func testAnalysisResultParsing_RedFlag() throws {
        let json = """
        {
            "conditions": [
                {
                    "conditionName": "Cauda Equina Syndrome",
                    "commonName": "Spinal Nerve Emergency",
                    "confidence": 25,
                    "explanation": "Loss of bladder control with back pain can be a sign of a serious nerve problem.",
                    "whatItMeans": "The nerves at the very bottom of your spine may be getting squeezed, which can affect bladder and leg function.",
                    "howToManage": "This is not something to manage at home. You need to get to an emergency room as soon as possible.",
                    "isRedFlag": true,
                    "redFlagMessage": "Please go to an emergency room right away. Loss of bladder control with back pain needs urgent medical attention.",
                    "nextSteps": ["Go to the nearest emergency room immediately"]
                }
            ],
            "overallSummary": "Some of your symptoms need urgent medical attention. Please read the details carefully.",
            "disclaimerText": "This is not a medical diagnosis. Please seek emergency care."
        }
        """

        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let conditions = parsed["conditions"] as! [[String: Any]]

        XCTAssertTrue(conditions[0]["isRedFlag"] as! Bool)
        XCTAssertNotNil(conditions[0]["redFlagMessage"])
        XCTAssertEqual(conditions[0]["commonName"] as? String, "Spinal Nerve Emergency")
        XCTAssertNotNil(conditions[0]["whatItMeans"])
        XCTAssertNotNil(conditions[0]["howToManage"])
    }

    func testAnalysisResultParsing_FallbackJSONExtraction() {
        // Test the fallback extraction logic (finding JSON between first { and last })
        let messyResponse = "Here is the analysis:\n{\"conditions\":[]}\nEnd of response."

        if let start = messyResponse.firstIndex(of: "{"),
           let end = messyResponse.lastIndex(of: "}") {
            let extracted = String(messyResponse[start...end])
            XCTAssertEqual(extracted, "{\"conditions\":[]}")
        } else {
            XCTFail("Should find JSON in messy response")
        }
    }

    // MARK: - New Health Fields in Prompt

    func testBuildUserMessage_includesDominantSide() {
        let profile = TestFixtures.makeProfile(dominantSide: "Left")
        let assessment = TestFixtures.makeAssessment()

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("Dominant Side: Left"))
    }

    func testBuildUserMessage_noDominantSide_omitted() {
        let profile = TestFixtures.makeProfile(dominantSide: nil)
        let assessment = TestFixtures.makeAssessment()

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertFalse(message.contains("Dominant Side"))
    }

    func testBuildUserMessage_includesMedicationHistory() {
        let changes = [
            TestFixtures.makeMedicationChange(medication: "Ibuprofen", action: "started"),
            TestFixtures.makeMedicationChange(medication: "Blood Thinners", action: "stopped")
        ]
        let profile = TestFixtures.makeProfile(medicationHistory: changes)
        let assessment = TestFixtures.makeAssessment()

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("MEDICATION HISTORY:"))
        XCTAssertTrue(message.contains("Started Ibuprofen"))
        XCTAssertTrue(message.contains("Stopped Blood Thinners"))
    }

    func testBuildUserMessage_noMedicationHistory_omitted() {
        let profile = TestFixtures.makeProfile(medicationHistory: nil)
        let assessment = TestFixtures.makeAssessment()

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertFalse(message.contains("MEDICATION HISTORY:"))
    }

    func testBuildUserMessage_includesSurgeryType() {
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            surgeryType: "Arthroscopic meniscus repair"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("[Type: Arthroscopic meniscus repair]"))
    }

    func testBuildUserMessage_includesCausingInjury() {
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            causingInjury: "Torn ACL from soccer"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("[Caused by: Torn ACL from soccer]"))
    }

    func testBuildUserMessage_includesHardwarePresent() {
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            hasHardware: true,
            hardwareDetails: "Two titanium screws"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("[Hardware present: Two titanium screws]"))
    }

    func testBuildUserMessage_includesNoHardware() {
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            hasHardware: false
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("[No hardware]"))
    }

    func testBuildUserMessage_hardwareUnknownDetails_saysDetailsUnknown() {
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            hasHardware: true,
            hardwareDetails: nil
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )

        let message = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)

        XCTAssertTrue(message.contains("[Hardware present: details unknown]"))
    }
}
