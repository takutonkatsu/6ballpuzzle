import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../purchases/ad_removal_purchase_manager.dart';
import '../theme/game_theme_colors.dart';

class AdRemovalPurchaseLauncher {
  AdRemovalPurchaseLauncher._();

  static bool _isStartingPurchase = false;

  static Future<void> startFromBanner(BuildContext context) async {
    if (_isStartingPurchase ||
        !AppSettings.instance.canShowAdRemovalUi ||
        AppSettings.instance.adsRemoved.value) {
      return;
    }
    _isStartingPurchase = true;
    try {
      final manager = AdRemovalPurchaseManager.instance;
      final ready = await manager.initialize();
      if (!context.mounted) {
        return;
      }
      if (!ready || !manager.isConfigured) {
        await _showPurchaseError(
          context,
          manager.lastInitializationError,
        );
        return;
      }

      final started = await manager.buy();
      if (!started && context.mounted) {
        await _showPurchaseError(
          context,
          manager.lastInitializationError,
        );
      }
    } finally {
      _isStartingPurchase = false;
    }
  }

  static Future<void> _showPurchaseError(
    BuildContext context,
    String? detail,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141421),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: GameThemeColors.cyan.withValues(alpha: 0.75),
              width: 1.4,
            ),
          ),
          title: const Text(
            '購入エラー',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            detail == null || detail.isEmpty
                ? '購入を開始できませんでした。しばらくしてからお試しください。'
                : '購入を開始できませんでした。\n$detail',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                '閉じる',
                style: TextStyle(
                  color: GameThemeColors.cyan,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
