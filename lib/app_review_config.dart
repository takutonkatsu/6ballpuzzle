class AppReviewConfig {
  AppReviewConfig._();

  static const bool _isNonProdFlavor = String.fromEnvironment(
        'FLAVOR',
        defaultValue: bool.fromEnvironment('dart.vm.product') ? 'prod' : 'dev',
      ) !=
      'prod';
  static const bool isProdFlavor = !_isNonProdFlavor;

  static const bool debugMenuEnabled = bool.fromEnvironment(
    'ENABLE_DEBUG_MENU',
    defaultValue: _isNonProdFlavor,
  );
  static const bool adRemovalGiftCodeEnabled = bool.fromEnvironment(
    'ENABLE_AD_REMOVAL_GIFT_CODE',
    defaultValue: true,
  );
  static const bool adRemovalGiftCodeIssuerEnabled = bool.fromEnvironment(
    'ENABLE_AD_REMOVAL_GIFT_CODE_ISSUER',
    defaultValue: _isNonProdFlavor,
  );
  static const bool useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: _isNonProdFlavor,
  );

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://takutonkatsu.github.io/Hexagon/privacy.html',
  );
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'takutonkatsu.dev@gmail.com',
  );

  static const String iosBannerAdUnitId = String.fromEnvironment(
    'IOS_BANNER_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/8827312040',
  );
  static const String androidBannerAdUnitId = String.fromEnvironment(
    'ANDROID_BANNER_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/1708511560',
  );
  static const String iosInterstitialAdUnitId = String.fromEnvironment(
    'IOS_INTERSTITIAL_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/8175515863',
  );
  static const String androidInterstitialAdUnitId = String.fromEnvironment(
    'ANDROID_INTERSTITIAL_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/7102332689',
  );
  static const String iosRewardedAdUnitId = String.fromEnvironment(
    'IOS_REWARDED_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/4118834283',
  );
  static const String androidRewardedAdUnitId = String.fromEnvironment(
    'ANDROID_REWARDED_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-5703232072169520/1672852543',
  );

  static const String iosAdRemovalProductId = String.fromEnvironment(
    'IOS_AD_REMOVAL_PRODUCT_ID',
    defaultValue: 'hexagon_remove_ads',
  );
  static const String adRemovalProductId = String.fromEnvironment(
    'AD_REMOVAL_PRODUCT_ID',
    defaultValue: 'remove_ads',
  );
  static const String androidAdRemovalProductId = String.fromEnvironment(
    'ANDROID_AD_REMOVAL_PRODUCT_ID',
    defaultValue: 'hexagon_remove_ads',
  );

  static bool get hasPrivacyPolicy => privacyPolicyUrl.trim().isNotEmpty;
  static bool get hasSupportEmail => supportEmail.trim().isNotEmpty;
  static bool get hasAdRemovalProduct =>
      adRemovalProductId.trim().isNotEmpty ||
      iosAdRemovalProductId.trim().isNotEmpty ||
      androidAdRemovalProductId.trim().isNotEmpty;
}
