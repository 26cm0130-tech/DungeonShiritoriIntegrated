# Firebase cross-device leaderboard setup

The app stores the `trial` and `random` TOP 100 lists in Cloud Firestore. It signs players in anonymously, so no sign-in screen is needed. Each installation can edit the names on its own records.

## Firebase Console

1. Confirm the iOS app registration matches the bundle identifier in `GoogleService-Info.plist`.
2. Enable **Authentication → Sign-in method → Anonymous**.
3. Create a **Cloud Firestore** database.
4. Deploy `firestore.rules` and `firestore.indexes.json` (Firebase CLI: `firebase deploy --only firestore:rules,firestore:indexes`).
5. Confirm App Check is configured before enabling enforcement for production traffic.

The project includes the Firebase Auth and Firestore Swift Package products and the app calls `FirebaseApp.configure()` at launch. Keep `GoogleService-Info.plist` in the application target resources for builds on other devices.

The client enforces the TOP 100 query and rules restrict score creation to authenticated users, owner-only name changes, and server timestamps. A client-provided clear time is still not proof of gameplay; use a trusted game server or callable Cloud Function if tamper-resistant scores are required.
