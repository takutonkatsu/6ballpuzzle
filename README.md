# six_ball_puzzle

A new Flutter project.

## Firebase flavor

Firebaseの接続先は `--dart-define=FLAVOR=...` で切り替わります。

- 開発時: `flutter run` または `flutter run --dart-define=FLAVOR=dev`
- 本番APKビルド時: `flutter build apk --release --dart-define=FLAVOR=prod`

### App Check

- `prod` では App Check が自動で有効になります。
- `dev` ではデフォルトで App Check を無効にしています。
- `dev` でも App Check を試す場合: `flutter run --dart-define=FLAVOR=dev --dart-define=ENABLE_APP_CHECK=true`
  - この場合は Firebase Console の App Check で debug token の登録が必要です。

### Realtime Database Rules deploy

環境分離後は、Realtime Database Rules を `dev` / `prod` それぞれの Firebase プロジェクトへ反映する必要があります。

- devへ反映: `firebase deploy --only database --project dev`
- prodへ反映: `firebase deploy --only database --project prod`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
