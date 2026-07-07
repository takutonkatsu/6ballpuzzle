import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../firebase_database_provider.dart';

enum InviteRedeemStatus {
  accepted,
  alreadyUsed,
  notEligible,
  expired,
  codeUsed,
  ownCode,
  notFound,
  disabled,
  invalid,
  failed,
}

class InviteRedeemResult {
  const InviteRedeemResult({
    required this.status,
    this.inviterName = '',
  });

  final InviteRedeemStatus status;
  final String inviterName;

  bool get accepted => status == InviteRedeemStatus.accepted;
}

class InviteManager {
  InviteManager._();

  static final InviteManager instance = InviteManager._();

  static const int rewardCoins = 50000;
  static const String localCodeKey = 'invite_own_code';
  static const String localStatusKey = 'invite_status';
  static const String localInviterUidKey = 'invite_inviter_uid';
  static const String localInviterNameKey = 'invite_inviter_name';
  static const String _playerAccountCreatedAtKey = 'player_account_created_at';

  static const String _pendingStatus = 'pending';
  static const String _completedStatus = 'completed';
  static const String _activeStatus = 'active';
  static const String _usedStatus = 'used';
  static const int friendInviteValidHours = 24;
  static const int friendInviteMaxUses = 3;
  static final DateTime _eligibleAccountCreatedAfter =
      DateTime.parse('2026-06-23T00:00:00+09:00');
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final RegExp _validCodePattern = RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$');

  final Random _random = Random.secure();

  Future<String> ensureInviteCode({
    required String displayName,
    required String publicId,
  }) async {
    final uid = await AuthManager.instance.ensureSignedIn();
    if (uid.isEmpty) {
      return '';
    }
    final prefs = await SharedPreferences.getInstance();
    final savedCode = normalizeCode(prefs.getString(localCodeKey) ?? '');
    if (isValidCode(savedCode) &&
        await _isReusableFriendInviteCode(savedCode, uid)) {
      await _publishInviteCode(
        code: savedCode,
        uid: uid,
        displayName: displayName,
        publicId: publicId,
      );
      return savedCode;
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      final code = _generateCode();
      final ref = AppFirebaseDatabase.ref().child('inviteCodes/$code');
      final payload = _codePayload(
        uid: uid,
        displayName: displayName,
        publicId: publicId,
      );
      final result = await ref.runTransaction((current) {
        if (current != null) {
          return Transaction.abort();
        }
        return Transaction.success(payload);
      });
      if (result.committed) {
        await prefs.setString(localCodeKey, code);
        return code;
      }
    }
    return '';
  }

  Future<InviteRedeemResult> redeemCode(
    String rawCode, {
    required String inviteeName,
    required String inviteePublicId,
  }) async {
    final code = normalizeCode(rawCode);
    if (!isValidCode(code)) {
      return const InviteRedeemResult(status: InviteRedeemStatus.invalid);
    }

    final uid = await AuthManager.instance.ensureSignedIn();
    if (uid.isEmpty) {
      return const InviteRedeemResult(status: InviteRedeemStatus.failed);
    }
    if (!await _isEligibleNewInvitee()) {
      return const InviteRedeemResult(status: InviteRedeemStatus.notEligible);
    }

    try {
      final codeSnapshot = await AppFirebaseDatabase.ref()
          .child('inviteCodes/$code')
          .get()
          .timeout(const Duration(seconds: 5));
      final rawCodeData = codeSnapshot.value;
      if (rawCodeData is! Map) {
        return const InviteRedeemResult(status: InviteRedeemStatus.notFound);
      }
      final inviterUid = rawCodeData['uid']?.toString() ?? '';
      final inviterName = rawCodeData['displayName']?.toString() ?? 'プレイヤー';
      final expiresAt = _intValue(rawCodeData['expiresAt']);
      final maxUses = _intValue(rawCodeData['maxUses']);
      final usedCount = _intValue(rawCodeData['usedCount']);
      final usedUids = rawCodeData['usedUids'];
      final status = rawCodeData['status']?.toString() ?? _activeStatus;
      final eligibleInviteeDateKey =
          rawCodeData['eligibleInviteeDateKey']?.toString() ??
              rawCodeData['inviteDateKey']?.toString() ??
              '';
      if (rawCodeData['disabled'] == true) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.disabled,
          inviterName: inviterName,
        );
      }
      if (inviterUid.isEmpty) {
        return const InviteRedeemResult(status: InviteRedeemStatus.notFound);
      }
      if (status != _activeStatus) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.codeUsed,
          inviterName: inviterName,
        );
      }
      if (usedUids is Map && usedUids.containsKey(uid)) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.alreadyUsed,
          inviterName: inviterName,
        );
      }
      if (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.expired,
          inviterName: inviterName,
        );
      }
      if (maxUses > 0 && usedCount >= maxUses) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.codeUsed,
          inviterName: inviterName,
        );
      }
      if (!await _isEligibleNewInvitee(
        inviteDateKey: eligibleInviteeDateKey,
      )) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.notEligible,
          inviterName: inviterName,
        );
      }
      if (inviterUid == uid) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.ownCode,
          inviterName: inviterName,
        );
      }

      final claimRef = AppFirebaseDatabase.ref().child('inviteClaims/$uid');
      final existingClaim = await claimRef.get().timeout(
            const Duration(seconds: 5),
          );
      if (existingClaim.exists) {
        final prefs = await SharedPreferences.getInstance();
        final existing = existingClaim.value;
        if (existing is Map && existing['status'] == _completedStatus) {
          await prefs.setString(localStatusKey, _completedStatus);
        }
        return InviteRedeemResult(
          status: InviteRedeemStatus.alreadyUsed,
          inviterName: inviterName,
        );
      }

      final codeRef = AppFirebaseDatabase.ref().child('inviteCodes/$code');
      final reserveResult = await codeRef.runTransaction((current) {
        if (current is! Map) {
          return Transaction.abort();
        }
        final currentInviterUid = current['uid']?.toString() ?? '';
        final currentStatus = current['status']?.toString() ?? _activeStatus;
        final currentExpiresAt = _intValue(current['expiresAt']);
        final currentMaxUses = _intValue(current['maxUses']);
        final currentUsedCount = _intValue(current['usedCount']);
        final currentUsedUids = current['usedUids'];
        if (currentUsedUids is Map && currentUsedUids.containsKey(uid)) {
          return Transaction.abort();
        }
        if (currentInviterUid.isEmpty ||
            currentInviterUid == uid ||
            currentStatus != _activeStatus ||
            (currentExpiresAt > 0 &&
                currentExpiresAt <= DateTime.now().millisecondsSinceEpoch) ||
            (currentMaxUses > 0 && currentUsedCount >= currentMaxUses)) {
          return Transaction.abort();
        }
        final nextUsedCount = currentUsedCount + 1;
        final nextStatus = currentMaxUses > 0 && nextUsedCount >= currentMaxUses
            ? _usedStatus
            : _activeStatus;
        return Transaction.success({
          ...current,
          'status': nextStatus,
          'usedCount': nextUsedCount,
          'usedUids': {
            if (currentUsedUids is Map) ...currentUsedUids,
            uid: {
              'publicId': inviteePublicId,
              'displayName': inviteeName,
              'usedAt': DateTime.now().millisecondsSinceEpoch,
            },
          },
        });
      }).timeout(const Duration(seconds: 5));
      if (!reserveResult.committed) {
        return InviteRedeemResult(
          status: InviteRedeemStatus.codeUsed,
          inviterName: inviterName,
        );
      }

      final claimResult = await claimRef.runTransaction((current) {
        if (current != null) {
          return Transaction.abort();
        }
        return Transaction.success({
          'invitedUid': uid,
          'inviterUid': inviterUid,
          'inviteCode': code,
          'status': _pendingStatus,
          'inviteType': 'friend',
          'inviteeDisplayName': inviteeName,
          'inviteePublicId': inviteePublicId,
          'createdAt': ServerValue.timestamp,
        });
      }).timeout(const Duration(seconds: 5));

      final prefs = await SharedPreferences.getInstance();
      if (!claimResult.committed) {
        final existing = claimResult.snapshot.value;
        if (existing is Map && existing['status'] == _completedStatus) {
          await prefs.setString(localStatusKey, _completedStatus);
        }
        return InviteRedeemResult(
          status: InviteRedeemStatus.alreadyUsed,
          inviterName: inviterName,
        );
      }

      await prefs.setString(localStatusKey, _pendingStatus);
      await prefs.setString(localInviterUidKey, inviterUid);
      await prefs.setString(localInviterNameKey, inviterName);
      return InviteRedeemResult(
        status: InviteRedeemStatus.accepted,
        inviterName: inviterName,
      );
    } catch (_) {
      return const InviteRedeemResult(status: InviteRedeemStatus.failed);
    }
  }

  Future<void> markCompletedLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localStatusKey, _completedStatus);
  }

  String normalizeCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length != 8) {
      return cleaned;
    }
    return '${cleaned.substring(0, 4)}-${cleaned.substring(4)}';
  }

  bool isValidCode(String code) => _validCodePattern.hasMatch(code);

  DateTime inviteExpiresAtFromNow() {
    return DateTime.now().add(const Duration(hours: friendInviteValidHours));
  }

  Future<bool> _isEligibleNewInvitee({String? inviteDateKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final createdAtRaw = prefs.getString(_playerAccountCreatedAtKey) ?? '';
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return false;
    }
    if (createdAt.toUtc().isBefore(_eligibleAccountCreatedAfter.toUtc())) {
      return false;
    }
    if (inviteDateKey == null || inviteDateKey.isEmpty) {
      return true;
    }
    return _dateKey(createdAt) == inviteDateKey;
  }

  Future<bool> _isReusableFriendInviteCode(String code, String uid) async {
    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('inviteCodes/$code')
          .get()
          .timeout(const Duration(seconds: 3));
      final value = snapshot.value;
      if (value is! Map) {
        return false;
      }
      if (value['uid']?.toString() != uid) {
        return false;
      }
      if ((value['status']?.toString() ?? _activeStatus) != _activeStatus) {
        return false;
      }
      final expiresAt = _intValue(value['expiresAt']);
      if (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        return false;
      }
      final maxUses = _intValue(value['maxUses']);
      final usedCount = _intValue(value['usedCount']);
      final inviteDateKey = value['inviteDateKey']?.toString() ?? '';
      return (maxUses <= 0 || usedCount < maxUses) &&
          inviteDateKey == _dateKey(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _publishInviteCode({
    required String code,
    required String uid,
    required String displayName,
    required String publicId,
  }) async {
    await AppFirebaseDatabase.ref().child('inviteCodes/$code').update({
      'displayName': displayName.trim().isEmpty ? 'プレイヤー' : displayName.trim(),
      'publicId': publicId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Map<String, Object?> _codePayload({
    required String uid,
    required String displayName,
    required String publicId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final inviteDateKey = _dateKey(DateTime.now());
    return {
      'uid': uid,
      'displayName': displayName.trim().isEmpty ? 'プレイヤー' : displayName.trim(),
      'publicId': publicId,
      'type': 'friend',
      'inviteDateKey': inviteDateKey,
      'eligibleInviteeDateKey': inviteDateKey,
      'status': _activeStatus,
      'maxUses': friendInviteMaxUses,
      'usedCount': 0,
      'expiresAt':
          now + const Duration(hours: friendInviteValidHours).inMilliseconds,
      'updatedAt': now,
      'createdAt': now,
    };
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _dateKey(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _generateCode() {
    String part() => List.generate(
          4,
          (_) => _alphabet[_random.nextInt(_alphabet.length)],
        ).join();
    return '${part()}-${part()}';
  }
}
