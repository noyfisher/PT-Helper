import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Records and mirrors the user's legal-document acceptance (Terms of Service /
/// Privacy Policy). The canonical record lives at `users/{uid}/consents/legal`;
/// a UserDefaults mirror lets the launch-time re-acceptance gate decide without
/// waiting on a network round-trip and keeps working offline.
@MainActor
final class ConsentService: ObservableObject {
    static let shared = ConsentService()

    /// The ToS version the user has on record (nil until loaded / never accepted).
    @Published var recordedTosVersion: String?
    /// True once `load()` has finished (from Firestore or the offline mirror).
    @Published var isLoaded = false

    private let db = Firestore.firestore()

    // MARK: - UserDefaults mirror keys

    enum MirrorKeys {
        static let tosVersion = "consent.tosVersion"
        static let healthDataPolicyVersion = "consent.healthDataPolicyVersion"
    }

    private init() {}

    // MARK: - Re-acceptance

    /// Whether the recorded ToS version is missing or older than the current one.
    var needsLegalReacceptance: Bool {
        ConsentPolicy.needsLegalReacceptance(recordedVersion: recordedTosVersion)
    }

    // MARK: - Health data consent (Washington MHMDA)

    /// True when the mirrored health-data policy version matches the current one
    /// (the user has given standalone opt-in consent for the current policy).
    var hasHealthDataConsent: Bool {
        UserDefaults.standard.string(forKey: MirrorKeys.healthDataPolicyVersion)
            == LegalContent.healthDataPolicyVersion
    }

    // MARK: - Load

    /// Hydrates from the offline mirror first (so the gate can decide immediately),
    /// then reads the authoritative record from Firestore and updates the mirror.
    /// Offline / errors fall back to the mirror. Always sets `isLoaded = true`.
    func load() async {
        // Hydrate from the mirror first.
        recordedTosVersion = UserDefaults.standard.string(forKey: MirrorKeys.tosVersion)

        guard let uid = Auth.auth().currentUser?.uid else {
            isLoaded = true
            return
        }

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("consents").document("legal").getDocument()
            let reconciledTos = ConsentPolicy.reconciledConsentVersion(
                readFailed: false,
                docExists: snapshot.exists,
                serverVersion: snapshot.data()?["tosVersion"] as? String,
                mirrorVersion: recordedTosVersion)
            recordedTosVersion = reconciledTos
            setMirror(reconciledTos, forKey: MirrorKeys.tosVersion)

            let healthSnapshot = try await db.collection("users").document(uid)
                .collection("consents").document("healthData").getDocument()
            let reconciledHealth = ConsentPolicy.reconciledConsentVersion(
                readFailed: false,
                docExists: healthSnapshot.exists,
                serverVersion: healthSnapshot.data()?["policyVersion"] as? String,
                mirrorVersion: UserDefaults.standard.string(forKey: MirrorKeys.healthDataPolicyVersion))
            setMirror(reconciledHealth, forKey: MirrorKeys.healthDataPolicyVersion)
            objectWillChange.send()
        } catch {
            AppLogger.data.error("Error loading consent record: \(error.localizedDescription)")
            // Fall back to the already-hydrated mirror values.
        }
        isLoaded = true
    }

    private func setMirror(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Record

    /// Writes (merge) the current legal acceptance to Firestore and updates the
    /// published value + mirror. `source` is "onboarding", "reacceptance", or
    /// "skip_gate". `dateOfBirth` is recorded only from the skip gate.
    func recordLegalAcceptance(source: String, dateOfBirth: Date? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.data.error("recordLegalAcceptance: no signed-in user")
            return
        }

        var data: [String: Any] = [
            "tosVersion": LegalContent.tosVersion,
            "privacyPolicyVersion": LegalContent.privacyPolicyVersion,
            "acceptedAt": FieldValue.serverTimestamp(),
            "source": source,
            "appVersion": appVersion
        ]
        if let dateOfBirth {
            data["dateOfBirth"] = Timestamp(date: dateOfBirth)
        }

        db.collection("users").document(uid)
            .collection("consents").document("legal")
            .setData(data, merge: true) { error in
                if let error {
                    AppLogger.data.error("Failed to record legal acceptance: \(error.localizedDescription)")
                }
            }

        recordedTosVersion = LegalContent.tosVersion
        UserDefaults.standard.set(LegalContent.tosVersion, forKey: MirrorKeys.tosVersion)
    }

    /// Writes (merge) the standalone MHMDA health-data consent — collection AND
    /// sharing recorded as separate timestamps — to `users/{uid}/consents/healthData`
    /// and updates the mirror. Called only after BOTH consent checkboxes are ticked.
    func recordHealthDataConsent() {
        // Mirror first, unconditionally. `hasHealthDataConsent` reads only this
        // mirror, and the point-of-use gates (BodyMap3DView, WellnessGoalPickerView)
        // chain into the next screen from the sheet's onDismiss by re-reading it.
        // When the mirror was written only after the uid guard below, any state
        // with no Firebase user — the `--uitesting` auth bypass, a sign-out race —
        // dismissed the consent sheet without recording anything and dead-ended
        // the user on the body map. That is exactly why the four assessment
        // journey UI tests failed on every fresh simulator (the nightly runner)
        // while passing on a developer machine whose mirror was already set.
        UserDefaults.standard.set(LegalContent.healthDataPolicyVersion,
                                  forKey: MirrorKeys.healthDataPolicyVersion)
        objectWillChange.send()

        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.data.error("recordHealthDataConsent: no signed-in user; consent mirrored locally only")
            return
        }

        let data: [String: Any] = [
            "policyVersion": LegalContent.healthDataPolicyVersion,
            "collectionConsentAt": FieldValue.serverTimestamp(),
            "sharingConsentAt": FieldValue.serverTimestamp(),
            "appVersion": appVersion
        ]

        db.collection("users").document(uid)
            .collection("consents").document("healthData")
            .setData(data, merge: true) { error in
                if let error {
                    AppLogger.data.error("Failed to record health data consent: \(error.localizedDescription)")
                }
            }
    }

    /// MHMDA withdrawal: removes the consent assertion server-side while keeping
    /// an audit trail (revokedAt + prior timestamps survive; policyVersion is
    /// field-deleted so `load()` reconciliation treats it as unconsented on every
    /// device). Mirror cleared immediately so point-of-use gates re-fire this session.
    func revokeHealthDataConsent() {
        // Same ordering as recordHealthDataConsent: the local withdrawal must
        // take effect even when the server write cannot be attempted.
        UserDefaults.standard.removeObject(forKey: MirrorKeys.healthDataPolicyVersion)
        objectWillChange.send()

        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.data.error("revokeHealthDataConsent: no signed-in user; withdrawal mirrored locally only")
            return
        }
        db.collection("users").document(uid)
            .collection("consents").document("healthData")
            .setData([
                "policyVersion": FieldValue.delete(),
                "revokedAt": FieldValue.serverTimestamp(),
                "appVersion": appVersion
            ], merge: true) { error in
                if let error {
                    AppLogger.data.error("Failed to record consent withdrawal: \(error.localizedDescription)")
                }
            }
    }

    // MARK: - Local mirror lifecycle

    /// Removes both mirror keys (sign-out and account deletion).
    static func clearLocalMirrors() {
        UserDefaults.standard.removeObject(forKey: MirrorKeys.tosVersion)
        UserDefaults.standard.removeObject(forKey: MirrorKeys.healthDataPolicyVersion)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
