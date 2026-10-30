# Firebase設定と設定ファイルの扱い

このアプリにはFirebase Authentication（匿名認証）とCloud Firestoreを使った共有ランキングが実装されています。依存関係、Firestoreルール、インデックス、初期化コードはプロジェクトに含まれています。ランキングのFirebase Console側設定は [FIREBASE_RANKING_SETUP.md](FIREBASE_RANKING_SETUP.md) を参照してください。

## iOS設定ファイル

1. Firebase ConsoleでiOSアプリのBundle ID `jp.ac.jec.cm0130.Map` を確認し、`GoogleService-Info.plist` をダウンロードします。
2. ファイルを `Map/GoogleService-Info.plist` に置きます。このファイルは `.gitignore` 対象です。Xcodeの同期フォルダに含まれるため、ローカルにある場合はアプリのリソースとしてバンドルされます。
3. このファイルがない場合もアプリは起動し、ランキングは端末内保存にフォールバックします。クラウドランキングを使うにはFirebase設定ファイルが必要です。

## GitHub Actions

ビルド時だけ設定を使う場合は、ローカルのplistを1行のBase64文字列にしてコピーします。

```sh
base64 -i Map/GoogleService-Info.plist | tr -d '\\n' | pbcopy
```

GitHubリポジトリの **Settings → Secrets and variables → Actions** で `FIREBASE_IOS_PLIST_BASE64` というRepository Secretを作り、コピーした文字列を登録します。iOSビルドjobはSecretが利用できるときだけplistを一時復元し、ビルド後に作業領域から削除します。Secretが使えないfork由来のPull Requestでは復元を飛ばし、端末内ランキングでビルドします。

## APIキーについて

FirebaseのAPIキーはFirebaseプロジェクトを識別するための値で、Firestoreへのアクセス権限そのものではありません。iOSアプリに設定ファイルを含めると、配布されたアプリから値を確認できます。Gitから除外しても、アプリ利用者から完全に隠すことはできません。データ保護はFirestore Security Rules、匿名認証、必要に応じてApp Checkで行います。Firebase以外の有料Google Cloud APIキーやサーバー秘密鍵はアプリに含めず、サーバー側に保管してください。

`GoogleService-Info.plist` はGitの現在の追跡対象から外しています。過去のコミット履歴からは削除されないため、履歴上の値も消す必要がある場合は、履歴の書き換えとFirebase Console側のキー制限・更新を別途検討してください。
