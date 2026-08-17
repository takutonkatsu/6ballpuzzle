# Server Config Reference

サーバー側、主に Firebase Realtime Database からアプリ挙動を変更できる項目の一覧です。  
`database.rules.json` では `appConfig` と `userNotices` はクライアント書き込み不可なので、Firebase Console、Admin SDK、Functions、管理用スクリプトから更新してください。

## すぐ変更できるもの

| DBパス | 変更できる内容 | 主なキー | 反映タイミング |
| --- | --- | --- | --- |
| `appConfig/minSupportedBuild/{ios,android}` | 強制アップデート対象のビルド番号 | 数値。例: `50` | アプリ起動時 |
| `appConfig/minSupportedVersion/{ios,android}` | 強制アップデート画面に表示する必要バージョン名 | 文字列。例: `1.4.0` | アプリ起動時 |
| `appConfig/storeUrl/{ios,android}` | 強制アップデート画面のストアURL | 文字列URL | アプリ起動時 |
| `appConfig/updateMessage` | 強制アップデート画面の本文 | 文字列 | アプリ起動時 |
| `appConfig/maintenance/global` | アプリ全体をロード画面で停止 | `enabled`, `title`, `message`, `startsAt`, `expectedEndAt` | アプリ起動時 |
| `appConfig/maintenance/modes/{mode}` | 各モードの開始/マッチング停止 | `enabled`, `matchmakingDisabled`, `title`, `message`, `startsAt`, `expectedEndAt` | モード開始時、DB Rules判定時 |
| `appConfig/ads` | 全広告停止、広告削除課金導線の非表示 | `globallyDisabled` | アプリ起動時。その後はリアルタイム反映 |
| `appConfig/realtimeTransport` | WebSocket同期のON/OFF、接続先、モード別導入 | `enabled`, `shadowEnabled`, `receiveEnabled`, `url`, `allowInsecureEndpoint`, `modes.friend`, `modes.ranked`, `modes.arena` | 対人戦接続時。30秒キャッシュ |
| `appConfig/rankedMatchmaking` | ランク戦マッチング条件 | `botFallbackSeconds`, `rangeGrowthPerSecond` | ランク戦マッチング開始時。30秒キャッシュ |
| `appConfig/rankedMatchmakingHints` | ランク戦待機画面のヒント文 | `items` 配下に文字列、または `{ text, order, enabled }` | ランク戦待機画面表示時 |
| `appConfig/notices/{noticeId}` | 全体向けお知らせ | `enabled`, `title`, `message`, `publishedAt`, `startsAt`, `endsAt`, `minBuild`, `maxBuild`, `platforms` | ホーム画面のお知らせ取得時 |
| `appConfig/notice` | 旧形式の単一お知らせ | `enabled`, `title`, `message` など | ホーム画面のお知らせ取得時 |
| `userNotices/{uid}/{noticeId}` | 個別ユーザー向けお知らせ | 全体お知らせと同じ | ホーム画面のお知らせ取得時 |
| `appConfig/nameModeration` | 名前登録/変更時のNG判定 | `blockedWords`, `reservedWords`, `regexes` | 名前チェック時。10分キャッシュ |
| `adminGrants/{uid}/{grantId}` | 個別ユーザーへの未受取報酬付与 | `type`, `coins`, `title`, `message`, `createdAt`, `expiresAt` | アプリ起動時/プレイヤーデータ読込時 |
| `adminRatingLocks/{uid}/rating` | 特定ユーザーのランク戦レート固定 | `rating` | DB Rulesでランキング/ユーザー更新時 |

## 問い合わせ調査で見るログ

| DBパス | 確認できる内容 | 主な使い道 |
| --- | --- | --- |
| `rankedResultSyncLatest/{uid}` | 直近のランク戦ランキング反映結果 | 戦績はあるのにランキングへ載っていない/レートが反映されない時の初動確認 |
| `rankedResultSyncLogs/{uid}` | ランク戦ランキング反映の成功/失敗履歴 | どのシーズンID、レート、シーズン勝敗数、今日の勝利数で送信されたか確認 |
| `adminGrants/{uid}/{grantId}` | 未受取の個別付与報酬 | まだ受け取っていない報酬が残っているか確認 |
| `claimedAdminGrants/{uid}/{grantId}` | 個別付与報酬の受取済み履歴 | 補填やランキング報酬をユーザーが受け取ったか確認 |
| `expiredAdminGrants/{uid}/{grantId}` | 期限切れで削除された個別付与報酬 | 報酬が付与されたが期限切れで消えたのか確認 |
| `adminStats/rankedSeasonFinalizations/{seasonId}` | ランク戦シーズン確定時の概要 | シーズン終了時点の上位サンプル、確定件数確認 |
| `adminStats/rankedSeasonTransitions/{seasonId}` | ランク戦シーズン切替処理の実行結果 | シーズン切替時にリセットが完了したか確認 |
| `adminStats/rankedSeasonSanitizations/{seasonId}` | 新シーズンに混入した異常レート補正ログ | 前シーズンレートの混入や到達不能レートを補正したか確認 |
| `adminStats/dailyWinRankFinalizations/{date}` | 今日の勝利数ランキング報酬の確定ログ | 報酬対象者、勝利数、付与予定コインの確認 |
| `adminStats/adminGrantExpirationCleanups/{date}` | 期限切れ報酬の削除実行ログ | cleanupが実行され、何件期限切れ処理されたか確認 |

## モード名

`appConfig/maintenance/modes/{mode}` の `{mode}` は現在以下を使います。

| mode | 対象 |
| --- | --- |
| `ranked` | ランク戦 |
| `endless` | エンドレス |
| `friend` | フレンド対戦 |
| `cpu` | コンピュータ対戦 |
| `arena` | アリーナ。現在は実質未使用 |

## 設定例

### ランク戦だけメンテナンス

```json
{
  "appConfig": {
    "maintenance": {
      "modes": {
        "ranked": {
          "enabled": true,
          "title": "メンテナンス中",
          "message": "現在ランク戦はメンテナンス中です。完了までしばらくお待ちください。",
          "expectedEndAt": "2026-08-31T21:30:00+09:00"
        }
      }
    }
  }
}
```

### WebSocketをランク戦にも有効化

```json
{
  "appConfig": {
    "realtimeTransport": {
      "enabled": true,
      "shadowEnabled": true,
      "receiveEnabled": true,
      "url": "wss://realtime.hexagon.takutonkatsu.com",
      "modes": {
        "friend": true,
        "ranked": true,
        "arena": false
      }
    }
  }
}
```

### ランク戦マッチング条件

```json
{
  "appConfig": {
    "rankedMatchmaking": {
      "botFallbackSeconds": 10,
      "rangeGrowthPerSecond": 40
    }
  }
}
```

`botFallbackSeconds` は `3〜60`、`rangeGrowthPerSecond` は `0〜200` にアプリ側で丸められます。初期範囲はアプリ内固定で `±50` です。

### 全広告停止モード

```json
{
  "appConfig": {
    "ads": {
      "globallyDisabled": true
    }
  }
}
```

`true` にすると、広告削除課金と同等のゲーム内特典を有効にした上で、リワード広告、インタースティシャル広告、広告SDKの読み込みを停止します。ホーム/設定の広告削除課金ボタンと、ショップの広告ガチャボタンも非表示になります。購入済みフラグ `adsRemoved` 自体は変更しないため、広告削除課金の購入者一覧とは区別されます。未設定または `false` で通常運用です。

### ランク戦待機ヒント

```json
{
  "appConfig": {
    "rankedMatchmakingHints": {
      "items": {
        "001": {
          "text": "フォーメーションは土台作りが9割。",
          "order": 1,
          "enabled": true
        },
        "002": {
          "text": "負けたら深呼吸。次の一手からまた始まります。",
          "order": 2,
          "enabled": true
        }
      }
    }
  }
}
```

`items` は文字列配列でも動きますが、並び替えや一時停止を考えると `{ text, order, enabled }` 形式が扱いやすいです。

### 全体お知らせ

```json
{
  "appConfig": {
    "notices": {
      "notice_20260806_hint_guide": {
        "enabled": true,
        "title": "ヒントガイド機能を追加しました",
        "message": "コンピュータ対戦とフレンド対戦で、置き場所のヒントを表示できるようになりました。",
        "publishedAt": "2026-08-06T09:00:00+09:00",
        "startsAt": "2026-08-06T09:00:00+09:00",
        "endsAt": "2026-08-31T21:00:00+09:00",
        "platforms": ["all"]
      }
    }
  }
}
```

### 個別お知らせ

```json
{
  "userNotices": {
    "USER_UID": {
      "notice_reward_fix": {
        "enabled": true,
        "title": "補填のお知らせ",
        "message": "不具合のお詫びとしてコインを付与しました。",
        "publishedAt": "2026-08-06T09:00:00+09:00"
      }
    }
  }
}
```

### 名前NG設定

```json
{
  "appConfig": {
    "nameModeration": {
      "blockedWords": ["不適切語"],
      "reservedWords": ["運営", "admin"],
      "regexes": ["悪質な正規表現パターン"]
    }
  }
}
```

正規表現が壊れている場合、そのパターンだけ無視されます。

## DB変更だけでは変えられないもの

以下は現在アプリ内または Functions 内に固定されているため、変更にはコード修正とデプロイが必要です。

| 項目 | 現状 |
| --- | --- |
| ランキング報酬額 | Functions内の報酬テーブル |
| 招待報酬額 | `50,000` コイン固定 |
| デイリー挑戦回数 | アプリ内固定 |
| 30分広告なしチケット価格/時間 | アプリ内固定 |
| インタースティシャル広告の予約間隔 | アプリ内固定 |
| ミッション内容/報酬 | アプリ内固定 |
| ガチャ排出内容/価格 | アプリ内固定 |
| シーズン切替時刻/自動メンテ時間 | アプリ内固定 |
