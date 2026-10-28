import FirebaseAuth
import FirebaseFirestore
import Foundation

enum FirebaseLeaderboardError: Error {
    case authenticationFailed
    case invalidRecord
    case recordNotOwned
}

/// 匿名認証したプレイヤーの記録をFirestoreのモード別TOP100へ保存する。
final class FirebaseLeaderboardStore {
    static let shared = FirebaseLeaderboardStore()
    private let database = Firestore.firestore()
    private let limit = 100

    private init() {}

    func load(_ mode: LeaderboardMode) async throws -> [LeaderboardEntry] {
        _ = try await authenticatedUserID()
        let snapshot = try await collection(for: mode)
            .order(by: "clearTime")
            .order(by: "recordedAt")
            .limit(to: limit)
            .getDocuments()

        return LocalLeaderboard.sortedEntries(snapshot.documents.compactMap(decode))
    }

    func submit(_ entry: LeaderboardEntry, to mode: LeaderboardMode) async throws -> [LeaderboardEntry] {
        guard entry.isValidForSubmission else { throw FirebaseLeaderboardError.invalidRecord }
        let userID = try await authenticatedUserID()
        var data: [String: Any] = [
            "ownerUID": userID,
            "playerName": entry.playerName,
            "clearTime": entry.clearTime,
            "recordedAt": FieldValue.serverTimestamp()
        ]
        if let seed = entry.seed {
            data["seed"] = String(seed)
        }
        try await collection(for: mode).document(entry.id.uuidString).setData(data)
        return try await load(mode)
    }

    func updateName(for entryID: UUID, to name: String, in mode: LeaderboardMode) async throws -> [LeaderboardEntry] {
        guard let cleanName = LeaderboardEntry.cleanedPlayerName(name) else {
            throw FirebaseLeaderboardError.invalidRecord
        }
        let userID = try await authenticatedUserID()
        let document = collection(for: mode).document(entryID.uuidString)
        let snapshot = try await document.getDocument()
        guard snapshot.data()?["ownerUID"] as? String == userID else {
            throw FirebaseLeaderboardError.recordNotOwned
        }
        try await document.updateData(["playerName": cleanName])
        return try await load(mode)
    }

    private func authenticatedUserID() async throws -> String {
        if let userID = Auth.auth().currentUser?.uid { return userID }
        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let userID = result?.user.uid {
                    continuation.resume(returning: userID)
                } else {
                    continuation.resume(throwing: error ?? FirebaseLeaderboardError.authenticationFailed)
                }
            }
        }
    }

    private func collection(for mode: LeaderboardMode) -> CollectionReference {
        database.collection("leaderboards").document(mode.rawValue).collection("entries")
    }

    private func decode(_ document: QueryDocumentSnapshot) -> LeaderboardEntry? {
        guard let id = UUID(uuidString: document.documentID) else { return nil }
        let data = document.data()
        guard
              let name = data["playerName"] as? String,
              let time = data["clearTime"] as? Double,
              let timestamp = data["recordedAt"] as? Timestamp else { return nil }
        let seed = (data["seed"] as? String).flatMap(UInt64.init)
        return LeaderboardEntry(
            id: id,
            playerName: name,
            clearTime: time,
            recordedAt: timestamp.dateValue(),
            seed: seed
        )
    }
}
