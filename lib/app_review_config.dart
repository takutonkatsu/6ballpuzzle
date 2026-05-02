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
      String.fromEnvironment('IOS_BANNER_AD_UNIT_ID');
  static const String androidBannerAdUnitId =
      String.fromEnvironment('ANDROID_BANNER_AD_UNIT_ID');
  static const String iosInterstitialAdUnitId =
      String.fromEnvironment('IOS_INTERSTITIAL_AD_UNIT_ID');
  static const String androidInterstitialAdUnitId =
      String.fromEnvironment('ANDROID_INTERSTITIAL_AD_UNIT_ID');
  static const String iosRewardedAdUnitId =
      String.fromEnvironment('IOS_REWARDED_AD_UNIT_ID');
  static const String androidRewardedAdUnitId =
      String.fromEnvironment('ANDROID_REWARDED_AD_UNIT_ID');

  static const String adRemovalProductId =
      String.fromEnvironment('AD_REMOVAL_PRODUCT_ID');

  static bool get hasPrivacyPolicy => privacyPolicyUrl.trim().isNotEmpty;
  static bool get hasSupportEmail => supportEmail.trim().isNotEmpty;
  static bool get hasAdRemovalProduct => adRemovalProductId.trim().isNotEmpty;
}
