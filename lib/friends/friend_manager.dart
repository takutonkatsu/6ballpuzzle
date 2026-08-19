import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

import '../auth/auth_manager.dart';
import '../firebase_database_provider.dart';

class FriendManager {
  FriendManager._();

  static final FriendManager instance = FriendManager._();
  static const int maxFriends = 10;
  static const Duration linkTtl = Duration(hours: 24);
  static const Duration inviteTtl = Duration(minutes: 5);
  static const String friendLinkBaseUrl =
      'https://takutonkatsu.com/Hexagon/friend/';
  static const String friendAppLinkBaseUrl = 'hexagon://friend';

  final DatabaseReference _db = AppFirebaseDatabase.ref();
  final Random _random = Random.secure();

  Future<String> createFriendCode() async {
    final uid = await AuthManager.instance.ensureSignedIn();
    for (var attempt = 0; attempt < 12; attempt++) {
      final code = _randomCode();
      final ref = _db.child('friendLinks/$code');
      final existing = await ref.get();
      if (existing.exists) {
        continue;
      }
      await ref.set({
        'ownerUid': uid,
        'createdAt': ServerValue.timestamp,
        'expiresAt': DateTime.now().add(linkTtl).millisecondsSinceEpoch,
      });
      return code;
    }
    throw StateError('フレンドコードの生成に失敗しました。');
  }

  String friendUrlForCode(String code) => '$friendLinkBaseUrl?code=$code';

  String friendAppUrlForCode(String code) => '$friendAppLinkBaseUrl?code=$code';

  Future<FriendAddResult> addFriendByCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      return const FriendAddResult(
        status: FriendAddStatus.invalid,
        message: 'フレンドコードが空です。',
      );
    }
    final myUid = await AuthManager.instance.ensureSignedIn();
    final linkSnapshot = await _db.child('friendLinks/$normalized').get();
    if (!linkSnapshot.exists) {
      return const FriendAddResult(
        status: FriendAddStatus.invalid,
        message: 'フレンドコードが見つかりません。',
      );
    }
    final link = _mapValue(linkSnapshot.value);
    final ownerUid = _stringValue(link['ownerUid']);
    final expiresAt = _intValue(link['expiresAt']) ?? 0;
    if (ownerUid == null || ownerUid.isEmpty) {
      return const FriendAddResult(
        status: FriendAddStatus.invalid,
        message: 'フレンドコードが無効です。',
      );
    }
    if (ownerUid == myUid) {
      return const FriendAddResult(
        status: FriendAddStatus.self,
        message: '自分自身はフレンドに追加できません。',
      );
    }
    if (expiresAt > 0 && DateTime.now().millisecondsSinceEpoch > expiresAt) {
      return const FriendAddResult(
        status: FriendAddStatus.expired,
        message: 'フレンドコードの有効期限が切れています。',
      );
    }
    if ((await _db.child('friends/$myUid/$ownerUid').get()).exists) {
      return const FriendAddResult(
        status: FriendAddStatus.alreadyFriends,
        message: 'すでにフレンドです。',
      );
    }
    final myCount = await _friendCount(myUid);
    if (myCount >= maxFriends) {
      return const FriendAddResult(
        status: FriendAddStatus.limitReached,
        message: 'フレンド上限に達しています。',
      );
    }
    await _db.update({
      'friends/$myUid/$ownerUid/addedAt': ServerValue.timestamp,
      'friends/$ownerUid/$myUid/addedAt': ServerValue.timestamp,
    });
    final ownerProfile = await _db.child('publicProfiles/$ownerUid').get();
    final ownerName =
        _stringValue(_mapValue(ownerProfile.value)['displayName']) ?? 'プレイヤー';
    return FriendAddResult(
      status: FriendAddStatus.added,
      message: '$ownerNameをフレンドに追加しました。',
    );
  }

  Future<List<FriendEntry>> fetchFriends() async {
    final uid = await AuthManager.instance.ensureSignedIn();
    final snapshot = await _db.child('friends/$uid').get();
    final friends =
        _mapValue(snapshot.value).keys.map((key) => '$key').toList();
    final entries = <FriendEntry>[];
    for (final friendUid in friends.take(maxFriends)) {
      final data = await Future.wait([
        _db.child('publicProfiles/$friendUid').get(),
        _db.child('friendPresence/$friendUid').get(),
      ]);
      final profile = _mapValue(data[0].value);
      final collection = _mapValue(profile['collection']);
      final ranked = _mapValue(profile['ranked']);
      final presence = _mapValue(data[1].value);
      entries.add(
        FriendEntry(
          uid: friendUid,
          displayName: _stringValue(profile['displayName']) ?? 'プレイヤー',
          publicId: _stringValue(profile['publicId']) ?? '',
          rating: _intValue(ranked['currentRating']) ?? 1000,
          playerIconId:
              _stringValue(collection['equippedPlayerIconId']) ?? 'default',
          playerIconFrameId:
              _stringValue(collection['equippedIconFrameId']) ?? 'default',
          profileBannerId:
              _stringValue(collection['equippedProfileBannerId']) ?? 'default',
          equippedBadgeIds: _stringListValue(collection['equippedBadgeIds']),
          online: presence['online'] == true,
          inBattle: presence['inBattle'] == true,
          activityMode: _stringValue(presence['mode']) ?? '',
        ),
      );
    }
    entries.sort((a, b) => b.rating.compareTo(a.rating));
    return entries;
  }

  Stream<FriendBattleInvite?> watchLatestInvite() async* {
    final uid = await AuthManager.instance.ensureSignedIn();
    yield* _db.child('friendInvites/$uid').onValue.map((event) {
      final invites = _mapValue(event.snapshot.value);
      FriendBattleInvite? latest;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in invites.entries) {
        final data = _mapValue(entry.value);
        if (_stringValue(data['status']) != 'pending') {
          continue;
        }
        final expiresAt = _intValue(data['expiresAt']) ?? 0;
        if (expiresAt > 0 && now > expiresAt) {
          continue;
        }
        final invite = FriendBattleInvite(
          id: '${entry.key}',
          fromUid: _stringValue(data['fromUid']) ?? '',
          fromName: _stringValue(data['fromName']) ?? 'フレンド',
          roomId: _stringValue(data['roomId']) ?? '',
          createdAt: _intValue(data['createdAt']) ?? 0,
        );
        if (invite.fromUid.isEmpty || invite.roomId.isEmpty) {
          continue;
        }
        if (latest == null || invite.createdAt > latest.createdAt) {
          latest = invite;
        }
      }
      return latest;
    });
  }

  Future<String> sendBattleInvite({
    required String friendUid,
    required String roomId,
    required String fromName,
  }) async {
    final myUid = await AuthManager.instance.ensureSignedIn();
    final inviteRef = _db.child('friendInvites/$friendUid').push();
    final inviteId = inviteRef.key;
    if (inviteId == null) {
      throw StateError('招待の作成に失敗しました。');
    }
    await inviteRef.set({
      'fromUid': myUid,
      'fromName': fromName,
      'roomId': roomId,
      'status': 'pending',
      'createdAt': ServerValue.timestamp,
      'expiresAt': DateTime.now().add(inviteTtl).millisecondsSinceEpoch,
    });
    return inviteId;
  }

  Future<void> updateInviteStatus({
    required String targetUid,
    required String inviteId,
    required String status,
  }) async {
    await _db.child('friendInvites/$targetUid/$inviteId').update({
      'status': status,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Stream<String> watchInviteStatus({
    required String targetUid,
    required String inviteId,
  }) {
    return _db.child('friendInvites/$targetUid/$inviteId').onValue.map((event) {
      final data = _mapValue(event.snapshot.value);
      return _stringValue(data['status']) ?? '';
    });
  }

  Future<void> deleteFriend(String friendUid) async {
    final myUid = await AuthManager.instance.ensureSignedIn();
    await _db.update({
      'friends/$myUid/$friendUid': null,
      'friends/$friendUid/$myUid': null,
    });
  }

  Future<void> markPresence({
    required bool online,
    bool inBattle = false,
    String mode = '',
  }) async {
    final uid = await AuthManager.instance.ensureSignedIn();
    final ref = _db.child('friendPresence/$uid');
    await ref.set({
      'online': online,
      'inBattle': inBattle,
      'mode': mode,
      'updatedAt': ServerValue.timestamp,
    });
    if (online) {
      await ref.onDisconnect().set({
        'online': false,
        'inBattle': false,
        'mode': '',
        'updatedAt': ServerValue.timestamp,
      });
    }
  }

  Future<int> _friendCount(String uid) async {
    final snapshot = await _db.child('friends/$uid').get();
    return _mapValue(snapshot.value).length;
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  static Map<dynamic, dynamic> _mapValue(Object? value) {
    if (value is Map) {
      return Map<dynamic, dynamic>.from(value);
    }
    return const {};
  }

  static String? _stringValue(Object? value) => value?.toString();

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}');
  }

  static List<String> _stringListValue(Object? value) {
    if (value is List) {
      return value.whereType<Object>().map((item) => item.toString()).toList();
    }
    if (value is Map) {
      return value.values
          .whereType<Object>()
          .map((item) => item.toString())
          .toList();
    }
    return const [];
  }
}

class FriendEntry {
  const FriendEntry({
    required this.uid,
    required this.displayName,
    required this.publicId,
    required this.rating,
    required this.playerIconId,
    required this.playerIconFrameId,
    required this.profileBannerId,
    required this.equippedBadgeIds,
    required this.online,
    required this.inBattle,
    required this.activityMode,
  });

  final String uid;
  final String displayName;
  final String publicId;
  final int rating;
  final String playerIconId;
  final String playerIconFrameId;
  final String profileBannerId;
  final List<String> equippedBadgeIds;
  final bool online;
  final bool inBattle;
  final String activityMode;
}

class FriendBattleInvite {
  const FriendBattleInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.roomId,
    required this.createdAt,
  });

  final String id;
  final String fromUid;
  final String fromName;
  final String roomId;
  final int createdAt;
}

enum FriendAddStatus {
  added,
  alreadyFriends,
  self,
  limitReached,
  targetLimitReached,
  invalid,
  expired,
}

class FriendAddResult {
  const FriendAddResult({
    required this.status,
    required this.message,
  });

  final FriendAddStatus status;
  final String message;
}
