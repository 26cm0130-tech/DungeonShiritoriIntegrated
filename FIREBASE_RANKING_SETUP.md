# Firebaseで機種間共有するランキングの設定

アプリは「試練の迷宮」と「ランダムステージ」のTOP 100をCloud Firestoreに保存します。匿名認証を使うため、プレイヤーのログイン画面は不要です。各端末から、自分が登録した記録の名前を変更できます。

## Firebase Consoleでの設定

1. iOSアプリの登録情報と `GoogleService-Info.plist` のBundle IDが一致していることを確認します。
2. **Authentication → Sign-in method → Anonymous** を有効にします。
3. **Cloud Firestore** データベースを作成します。
4. Firebase CLIで `firestore.rules` と `firestore.indexes.json` をデプロイします。

   ```sh
   firebase deploy --only firestore:rules,firestore:indexes
   ```

5. 本番環境でApp Checkの強制を有効にする前に、App Checkを設定してください。

プロジェクトにはFirebase AuthとFirestoreのSwift Packageが含まれており、アプリ起動時に `FirebaseApp.configure()` を呼び出します。他の端末でビルドする場合も、`GoogleService-Info.plist` をアプリターゲットのリソースに含めてください。

アプリはFirestoreから上位100件を取得します。セキュリティルールにより、認証済みユーザーだけが記録を作成でき、名前を変更できるのは記録の所有者だけです。登録日時にはサーバー時刻を使います。ただしクリアタイム自体はアプリから送信されるため、改ざんを防ぐ保証はありません。改ざんに強いランキングが必要な場合は、信頼できるゲームサーバーやCallable Cloud Functionでスコアを検証してください。
