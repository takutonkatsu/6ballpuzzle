
# six_ball_puzzle

A new Flutter project.

## Firebase flavor

Firebaseの接続先は `--dart-define=FLAVOR=...` で切り替わります。

- 開発時: `flutter run` または `flutter run --dart-define=FLAVOR=dev`
- 本番APKビルド時: `flutter build apk --release --dart-define=FLAVOR=prod`
- デバッグメニュー有効化: `--dart-define=ENABLE_DEBUG_MENU=true`

## App Store release defines

App Store提出ビルドでは、以下の値を実プロダクトのものに差し替えて指定してください。

- `PRIVACY_POLICY_URL`
- `SUPPORT_EMAIL`
- `AD_REMOVAL_PRODUCT_ID`
- `IOS_BANNER_AD_UNIT_ID`
- `IOS_INTERSTITIAL_AD_UNIT_ID`
- `IOS_REWARDED_AD_UNIT_ID`

例:

```bash
flutter build ipa --release \
  --dart-define=FLAVOR=prod \
  --dart-define=PRIVACY_POLICY_URL=https://example.com/privacy \
  --dart-define=SUPPORT_EMAIL=support@example.com \
  --dart-define=AD_REMOVAL_PRODUCT_ID=ad_removal \
  --dart-define=IOS_BANNER_AD_UNIT_ID=ca-app-pub-.../... \
  --dart-define=IOS_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-.../... \
  --dart-define=IOS_REWARDED_AD_UNIT_ID=ca-app-pub-.../...
```

## Firebase deploy

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
