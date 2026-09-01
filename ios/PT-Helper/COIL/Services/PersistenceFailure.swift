import SwiftUI

/// A write that did not reach the server, in a form the UI can surface.
///
/// Several flows shared one defect: the local array was updated optimistically,
/// the Firestore write failed, and the handler only wrote to `AppLogger`. The
/// user saw their workout or re-assessment listed as saved for the rest of the
/// session and found it gone after a relaunch — the worst version of this,
/// because it looks exactly like success until the data is needed.
///
/// This is a shared shape rather than five bespoke error paths so every flow
/// reports the same way and a new write site has an obvious thing to reach for.
struct PersistenceFailure: Identifiable, Equatable {
    let id = UUID()
    /// What failed, in the user's terms ("your workout", "your check-in").
    let subject: String
    /// Whether the value is still held locally and will be retried or can be
    /// re-entered — drives whether the copy promises recovery.
    let underlyingDescription: String

    var title: String { "Couldn't save \(subject)" }

    var message: String {
        "\(subject.prefix(1).uppercased() + subject.dropFirst()) is saved on this device but hasn't reached your account yet, "
        + "so it may not appear on your other devices or after reinstalling. Check your connection and try again."
    }

    static func == (lhs: PersistenceFailure, rhs: PersistenceFailure) -> Bool {
        lhs.subject == rhs.subject && lhs.underlyingDescription == rhs.underlyingDescription
    }
}

extension View {
    /// Present a persistence failure consistently wherever a write can fail.
    func persistenceFailureAlert(_ failure: Binding<PersistenceFailure?>) -> some View {
        alert(
            failure.wrappedValue?.title ?? "Couldn't save",
            isPresented: Binding(
                get: { failure.wrappedValue != nil },
                set: { if !$0 { failure.wrappedValue = nil } }
            ),
            presenting: failure.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { failure.wrappedValue = nil }
        } message: { item in
            Text(item.message)
        }
    }
}
