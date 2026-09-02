import XCTest
import FirebaseAuth
@testable import COIL

@MainActor
final class ConsentServiceTests: XCTestCase {

    override func tearDown() {
        ConsentService.clearLocalMirrors()
        super.tearDown()
    }

    // MARK: - reconciledConsentVersion

    func testReconciledConsentVersion_readFailed_keepsMirror() {
        let result = ConsentPolicy.reconciledConsentVersion(
            readFailed: true, docExists: false, serverVersion: nil, mirrorVersion: "2026.07")
        XCTAssertEqual(result, "2026.07")
    }

    func testReconciledConsentVersion_docMissing_clearsMirror() {
        let result = ConsentPolicy.reconciledConsentVersion(
            readFailed: false, docExists: false, serverVersion: nil, mirrorVersion: "2026.07")
        XCTAssertNil(result)
    }

    func testReconciledConsentVersion_fieldMissing_clearsMirror() {
        let result = ConsentPolicy.reconciledConsentVersion(
            readFailed: false, docExists: true, serverVersion: nil, mirrorVersion: "2026.07")
        XCTAssertNil(result)
    }

    func testReconciledConsentVersion_serverValue_wins() {
        let result = ConsentPolicy.reconciledConsentVersion(
            readFailed: false, docExists: true, serverVersion: "2026.08", mirrorVersion: "2026.07")
        XCTAssertEqual(result, "2026.08")
    }

    func testReconciledConsentVersion_docMissingAndNoMirror_staysNil() {
        let result = ConsentPolicy.reconciledConsentVersion(
            readFailed: false, docExists: false, serverVersion: nil, mirrorVersion: nil)
        XCTAssertNil(result)
    }

    // MARK: - hasHealthDataConsent

    func testHasHealthDataConsent_matchingMirror_isTrue() {
        UserDefaults.standard.set(LegalContent.healthDataPolicyVersion, forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)
        XCTAssertTrue(ConsentService.shared.hasHealthDataConsent)
    }

    func testHasHealthDataConsent_staleVersionMirror_isFalse() {
        UserDefaults.standard.set("2025.01", forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)
        XCTAssertFalse(ConsentService.shared.hasHealthDataConsent)
    }

    func testHasHealthDataConsent_missingMirror_isFalse() {
        UserDefaults.standard.removeObject(forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)
        XCTAssertFalse(ConsentService.shared.hasHealthDataConsent)
    }

    // MARK: - record / revoke without a signed-in user
    //
    // The unit-test host has no Firebase user, which is also the `--uitesting`
    // state. The mirror must still change so the point-of-use gates that
    // re-read `hasHealthDataConsent` from a sheet's onDismiss can continue.

    func testRecordHealthDataConsent_withoutSignedInUser_setsMirror() throws {
        try XCTSkipIf(Auth.auth().currentUser != nil, "requires no signed-in Firebase user")
        UserDefaults.standard.removeObject(forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)

        ConsentService.shared.recordHealthDataConsent()

        XCTAssertEqual(UserDefaults.standard.string(forKey: ConsentService.MirrorKeys.healthDataPolicyVersion),
                       LegalContent.healthDataPolicyVersion)
        XCTAssertTrue(ConsentService.shared.hasHealthDataConsent)
    }

    func testRevokeHealthDataConsent_withoutSignedInUser_clearsMirror() throws {
        try XCTSkipIf(Auth.auth().currentUser != nil, "requires no signed-in Firebase user")
        UserDefaults.standard.set(LegalContent.healthDataPolicyVersion, forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)

        ConsentService.shared.revokeHealthDataConsent()

        XCTAssertNil(UserDefaults.standard.string(forKey: ConsentService.MirrorKeys.healthDataPolicyVersion))
        XCTAssertFalse(ConsentService.shared.hasHealthDataConsent)
    }

    // MARK: - clearLocalMirrors

    func testClearLocalMirrors_removesBothKeys() {
        UserDefaults.standard.set("2026.07", forKey: ConsentService.MirrorKeys.tosVersion)
        UserDefaults.standard.set("2026.07", forKey: ConsentService.MirrorKeys.healthDataPolicyVersion)

        ConsentService.clearLocalMirrors()

        XCTAssertNil(UserDefaults.standard.string(forKey: ConsentService.MirrorKeys.tosVersion))
        XCTAssertNil(UserDefaults.standard.string(forKey: ConsentService.MirrorKeys.healthDataPolicyVersion))
    }
}
