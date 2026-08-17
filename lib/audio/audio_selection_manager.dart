import 'package:shared_preferences/shared_preferences.dart';

class AudioTrackSelection {
  const AudioTrackSelection({
    required this.id,
    required this.assetPath,
    required this.duration,
  });

  final String id;
  final String assetPath;
  final Duration duration;
}

class AudioSelectionManager {
  AudioSelectionManager._();

  static const String prefsPrefix = 'collection_audio_selection_';
  static const String ownedAudioIdsKey = 'collection_owned_audio_ids';
  static const String allAudioUnlockedPlayerName = 'たくとんかつ';
  static Set<String> _ownedAudioIds = {};

  static const AudioTrackSelection defaultHomeBgm = AudioTrackSelection(
    id: 'home_bgm_01',
    assetPath: 'audio/bgm_homeScreen01_Solid_State_Blue_Hero.mp3',
    duration: Duration(microseconds: 95908417),
  );

  static const AudioTrackSelection defaultBattleBgm = AudioTrackSelection(
    id: 'battle_bgm_01',
    assetPath: 'audio/bgm_battle01_8の字サーキット_2.mp3',
    duration: Duration(microseconds: 59917688),
  );

  static const Map<String, AudioTrackSelection> _homeBgmById = {
    'home_bgm_01': defaultHomeBgm,
    'home_bgm_02': AudioTrackSelection(
      id: 'home_bgm_02',
      assetPath: 'audio/bgm_homeScreen02_ドードドド・スタンピード.mp3',
      duration: Duration(microseconds: 60617667),
    ),
  };

  static const Map<String, AudioTrackSelection> _battleBgmById = {
    'battle_bgm_01': defaultBattleBgm,
    'battle_bgm_02': AudioTrackSelection(
      id: 'battle_bgm_02',
      assetPath: 'audio/bgm_battle02_Light_Ray.mp3',
      duration: Duration(microseconds: 81502042),
    ),
    'battle_bgm_03': AudioTrackSelection(
      id: 'battle_bgm_03',
      assetPath: 'audio/bgm_battle03_小さな台風のケビン.mp3',
      duration: Duration(microseconds: 84456000),
    ),
    'battle_bgm_04': AudioTrackSelection(
      id: 'battle_bgm_04',
      assetPath: 'audio/bgm_battle04_灼熱のユーロビート_2.mp3',
      duration: Duration(microseconds: 235464000),
    ),
    'battle_bgm_05': AudioTrackSelection(
      id: 'battle_bgm_05',
      assetPath: 'audio/bgm_battle05_渦巻く砂漠の風.mp3',
      duration: Duration(microseconds: 92640000),
    ),
    'battle_bgm_06': AudioTrackSelection(
      id: 'battle_bgm_06',
      assetPath: 'audio/bgm_battle06_有明のユーロビート_2.mp3',
      duration: Duration(microseconds: 126048000),
    ),
    'battle_bgm_07': AudioTrackSelection(
      id: 'battle_bgm_07',
      assetPath: 'audio/bgm_battle07_忘れてたー！_2.mp3',
      duration: Duration(microseconds: 80871938),
    ),
    'battle_bgm_08': AudioTrackSelection(
      id: 'battle_bgm_08',
      assetPath: 'audio/bgm_battle08バーゲンセール_2.mp3',
      duration: Duration(microseconds: 79881563),
    ),
    'battle_bgm_09': AudioTrackSelection(
      id: 'battle_bgm_09',
      assetPath: 'audio/bgm_battle09どたばたサーカス_2.mp3',
      duration: Duration(microseconds: 129009375),
    ),
    'battle_bgm_10': AudioTrackSelection(
      id: 'battle_bgm_10',
      assetPath: 'audio/bgm_battle10_迅雷のユーロビート_2.mp3',
      duration: Duration(microseconds: 122780437),
    ),
    'battle_bgm_11': AudioTrackSelection(
      id: 'battle_bgm_11',
      assetPath: 'audio/bgm_battle11_コミック☆はろはろ！.mp3',
      duration: Duration(microseconds: 70685833),
    ),
  };

  static const Map<String, Map<String, String>> _sfxFileBySectionAndId = {
    'ready': {
      'ready_01': 'readyGo01_メニューを開く3.mp3',
      'ready_02': 'readyGo02_メニューを開く2.mp3',
      'ready_03': 'readyGo03_3_2_1_GO!!!_レースのスタート音.mp3',
    },
    'load_screen': {
      'load_screen_01': 'loadScreen01_サウンドロゴ_3.mp3',
    },
    'winner': {
      'winner_01': 'winner01_jingle_22.mp3',
      'winner_02': 'winner02_jingle_10.mp3',
      'winner_03': 'winner03_レトロなゲームクリア音.mp3',
      'winner_04': 'winner04_ロボユーウィン.mp3',
      'winner_05': 'winner05_ミニファンファーレ.mp3',
      'winner_06': 'winner06_流れるようなゲームクリア音.mp3',
    },
    'loser': {
      'loser_01': 'loser01_jingle_24.mp3',
      'loser_02': 'loser02_失敗、ゲームオーバー.mp3',
      'loser_03': 'loser03_ティロリー.mp3',
      'loser_04': 'loser04＿ゲームオーバー.mp3',
      'loser_05': 'loser05_不穏なファンファーレ.mp3',
    },
    'button': {
      'button_01': 'buttonTap01_決定ボタンを押す44.mp3',
      'button_02': 'buttonTap02_選択2.mp3',
      'button_03': 'buttonTap03_8bit選択1.mp3',
      'button_04': 'buttonTap04_システム決定音_3.mp3',
      'button_05': 'buttonTap05_セレクト音風な効果音.mp3',
      'button_06': 'buttonTap06_マイクラアクション.mp3',
      'button_07': 'buttonTap07_マウスのクリック音.mp3',
    },
    'matching': {
      'matching_01': 'matching01_完了1.mp3',
      'matching_02': 'matching02_遭遇音.mp3',
      'matching_03': 'matching03_発見！成功！な嬉しい音.mp3',
      'matching_04': 'matching04_未来的な決定音、ボタン音.mp3',
      'matching_05': 'matching05_チープな正解音.mp3',
      'matching_06': 'matching06_8bit_Start.mp3',
      'matching_07': 'matching07_STAR_1（OK音、アイテム発見など）.mp3',
    },
    'formation': {
      'formation_01': 'formation01_メニューを開く4.mp3',
      'formation_02': 'formation02_決定ボタンを押す16.mp3',
      'formation_03': 'formation03_HP回復.mp3',
      'formation_04': 'formation04_おしゃれなテロップ表示音.mp3',
      'formation_05': 'formation05_切れ味パワーアップ.mp3',
      'formation_06': 'formation06_レベルアップ、回復.mp3',
      'formation_07': 'formation07_レベルアップ・経験値アップ.mp3',
    },
    'obstacle': {
      'obstacle_01': 'obstacleBallEffect01_データ表示3.mp3',
      'obstacle_02': 'obstacleBallEffect02_ラスボス・強敵が現れる時の音.mp3',
      'obstacle_03': 'obstacleBallEffect03_データなどを表示させる時の音.mp3',
      'obstacle_04': 'obstacleBallEffect04_ポイント大量獲得.mp3',
    },
    'spawn': {
      'spawn_01': 'spawn01_決定ボタンを押す33.mp3',
      'spawn_02': 'spawn02_決定ボタンを押す49.mp3',
      'spawn_03': 'spawn03_システム決定音_2.mp3',
    },
  };

  static const Set<String> syncedSfxSectionIds = {
    'ready',
    'load_screen',
    'winner',
    'loser',
    'button',
    'matching',
    'formation',
    'obstacle',
    'spawn',
  };

  static bool unlocksAllAudio(String playerName) {
    return playerName.trim() == allAudioUnlockedPlayerName;
  }

  static bool isDefaultAudioId(String id) {
    return id.endsWith('_01');
  }

  static bool isAudioUnlocked({
    required String playerName,
    required String itemId,
  }) {
    return unlocksAllAudio(playerName) ||
        isDefaultAudioId(itemId) ||
        _ownedAudioIds.contains(itemId);
  }

  static Future<void> setOwnedAudioItemIds(Iterable<String> itemIds) async {
    _ownedAudioIds = itemIds.where((id) => id.isNotEmpty).toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        ownedAudioIdsKey, _ownedAudioIds.toList()..sort());
  }

  static Future<void> loadOwnedAudioItemIds() async {
    final prefs = await SharedPreferences.getInstance();
    _ownedAudioIds = (prefs.getStringList(ownedAudioIdsKey) ?? const [])
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static String? sfxFileForId(String sectionId, String itemId) {
    return _sfxFileBySectionAndId[sectionId]?[itemId];
  }

  static String? audioFileForItemId(String itemId) {
    final homeBgm = _homeBgmById[itemId];
    if (homeBgm != null) {
      return homeBgm.assetPath.replaceFirst('audio/', '');
    }
    final battleBgm = _battleBgmById[itemId];
    if (battleBgm != null) {
      return battleBgm.assetPath.replaceFirst('audio/', '');
    }
    for (final section in _sfxFileBySectionAndId.values) {
      final fileName = section[itemId];
      if (fileName != null) {
        return fileName;
      }
    }
    return null;
  }

  static String sfxFileFromSelections(
    Map<String, String>? selections,
    String sectionId,
    String defaultFileName,
  ) {
    final selectedId = selections?[sectionId];
    if (selectedId == null) {
      return defaultFileName;
    }
    return sfxFileForId(sectionId, selectedId) ?? defaultFileName;
  }

  static Future<Map<String, String>> loadSelections() async {
    final prefs = await SharedPreferences.getInstance();
    final selections = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefsPrefix)) {
        continue;
      }
      final sectionId = key.substring(prefsPrefix.length);
      final itemId = prefs.getString(key);
      if (sectionId.isNotEmpty && itemId != null && itemId.isNotEmpty) {
        selections[sectionId] = itemId;
      }
    }
    return selections;
  }

  static Future<Map<String, String>> loadSyncedSfxSelections({
    required String playerName,
  }) async {
    final selections = await loadSelections();
    return {
      for (final entry in selections.entries)
        if (syncedSfxSectionIds.contains(entry.key) &&
            isAudioUnlocked(playerName: playerName, itemId: entry.value))
          entry.key: entry.value,
    };
  }

  static Future<void> restrictSelectionsForPlayer(String playerName) async {
    await loadOwnedAudioItemIds();
    if (unlocksAllAudio(playerName)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(prefsPrefix)) {
        continue;
      }
      final itemId = prefs.getString(key);
      if (itemId != null &&
          !isDefaultAudioId(itemId) &&
          !_ownedAudioIds.contains(itemId)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> saveSelection(String sectionId, String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefsPrefix$sectionId', itemId);
  }

  static Future<String> selectedSfxId(
    String sectionId,
    String defaultId,
  ) async {
    final sectionFiles = _sfxFileBySectionAndId[sectionId];
    if (sectionFiles == null) {
      return defaultId;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString('$prefsPrefix$sectionId');
    return sectionFiles.containsKey(selectedId) ? selectedId! : defaultId;
  }

  static Future<AudioTrackSelection> selectedHomeBgm() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString('${prefsPrefix}home_bgm');
    return _homeBgmById[selectedId] ?? defaultHomeBgm;
  }

  static Future<AudioTrackSelection> selectedBattleBgm() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString('${prefsPrefix}battle_bgm');
    return _battleBgmById[selectedId] ?? defaultBattleBgm;
  }

  static Future<String> selectedSfxFile(
    String sectionId,
    String defaultFileName,
  ) async {
    final sectionFiles = _sfxFileBySectionAndId[sectionId];
    if (sectionFiles == null) {
      return defaultFileName;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString('$prefsPrefix$sectionId');
    return sectionFiles[selectedId] ?? defaultFileName;
  }
}
