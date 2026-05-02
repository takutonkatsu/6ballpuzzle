class AppReviewConfig {
  AppReviewConfig._();

  static const bool _isNonProdFlavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev') != 'prod';

  static const bool debugMenuEnabled = bool.fromEnvironment(
    'ENABLE_DEBUG_MENU',
    defaultValue: _isNonProdFlavor,
  );

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://takutonkatsu.github.io/Hexagon/',
  );
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  static const String iosBannerAdUnitId =
      String.fromEnvironment(
        'IOS_BANNER_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/2934735716',
      );
  static const String androidBannerAdUnitId =
      String.fromEnvironment(
        'ANDROID_BANNER_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/6300978111',
      );
  static const String iosInterstitialAdUnitId =
      String.fromEnvironment(
        'IOS_INTERSTITIAL_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/4411468910',
      );
  static const String androidInterstitialAdUnitId =
      String.fromEnvironment(
        'ANDROID_INTERSTITIAL_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/1033173712',
      );
  static const String iosRewardedAdUnitId =
      String.fromEnvironment(
        'IOS_REWARDED_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/1712485313',
      );
  static const String androidRewardedAdUnitId =
      String.fromEnvironment(
        'ANDROID_REWARDED_AD_UNIT_ID',
        defaultValue: 'ca-app-pub-3940256099942544/5224354917',
      );

  static const String adRemovalProductId =
      String.fromEnvironment('AD_REMOVAL_PRODUCT_ID');

  static bool get hasPrivacyPolicy => privacyPolicyUrl.trim().isNotEmpty;
  static bool get hasSupportEmail => supportEmail.trim().isNotEmpty;
  static bool get hasAdRemovalProduct => adRemovalProductId.trim().isNotEmpty;
}
