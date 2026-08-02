# Hexagon Realtime Server

Firebase Realtime Databaseの対人戦同期をすぐに消さず、横に追加して検証するためのWebSocket中継サーバーです。

## 初回セットアップ

```bash
cd realtime_server
npm install
npm run build
cp .env.example .env
```

ローカル疎通だけを先に見る場合は、`.env`で次のようにします。

```env
ALLOW_UNVERIFIED_DEV_TOKENS=true
```

本番では必ず`false`に戻し、Firebase AdminのサービスアカウントJSONをDroplet上に配置して、`FIREBASE_SERVICE_ACCOUNT_PATH`にそのパスを設定します。

## DigitalOcean Dropletで起動

Droplet上でNode.js 22とpm2を入れます。

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2
```

サーバー一式をDropletへ配置したあと、Droplet上で実行します。

```bash
cd /opt/hexagon-realtime
npm ci
npm run build
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
```

疎通確認:

```bash
curl http://YOUR_DROPLET_IP:8080/health
```

成功すると`{"ok":true,...}`が返ります。

NginxとLet's Encryptを設定した本番では次で確認します。

```bash
curl https://realtime.hexagon.takutonkatsu.com/health
```

`/metrics`は本番では保護されます。`.env`または`ecosystem.config.cjs`で`METRICS_TOKEN`を設定した場合のみ、次のように確認できます。

```bash
curl "https://realtime.hexagon.takutonkatsu.com/metrics?token=YOUR_TOKEN"
```

## WebSocketプロトコル

接続直後、クライアントは5秒以内に`hello`を送ります。

```json
{
  "type": "hello",
  "token": "Firebase ID token",
  "roomId": "friend-room-id",
  "role": "host",
  "transportVersion": 1,
  "displayName": "プレイヤー"
}
```

以降は既存のRTDB同期イベントを小さなメッセージとして中継します。

```json
{
  "type": "activePiece",
  "seq": 120,
  "sentAt": 1760000000000,
  "payload": {
    "x": 2,
    "y": 5
  }
}
```

サーバーは相手へ次の形で転送します。

```json
{
  "type": "relay",
  "roomId": "friend-room-id",
  "from": {
    "uid": "firebase-uid",
    "role": "host"
  },
  "messageType": "activePiece",
  "seq": 120,
  "sentAt": 1760000000000,
  "serverAt": 1760000000030,
  "payload": {}
}
```

## 現時点の方針

- Firebase同期は残したままにします。
- まずフレンド対戦でシャドー送信、次に実同期へ切り替えます。
- ランク戦は安定確認後に移行します。
- ドメイン取得前はデバッグビルドのみ`ws://IP:8080`で検証できます。
- 本番配信ではNginxとLet's Encryptで`wss://`化します。
- アプリのリリースビルドでは、誤設定防止のため`wss://`以外は無効化します。

## アプリ側の切り替え設定

Realtime Databaseの`appConfig/realtimeTransport`で制御します。未設定または`enabled: false`なら、アプリは従来のFirebase同期のみで動きます。

最初の本番疎通では、フレンド対戦だけWebSocket優先にします。ランク戦はフレンド対戦で十分に安定確認してからONにします。

```json
{
  "enabled": true,
  "shadowEnabled": true,
  "receiveEnabled": true,
  "url": "wss://realtime.hexagon.takutonkatsu.com",
  "modes": {
    "friend": true,
    "ranked": false,
    "arena": false
  }
}
```

Firebase CLIで入れる場合:

```bash
firebase database:update /appConfig/realtimeTransport realtime-transport-config.json
```

`receiveEnabled`が`false`の間は、ゲーム本体の反映は従来のRealtime Databaseのままです。WebSocketサーバーが止まっても対戦進行には影響しません。

`receiveEnabled`を`true`にすると、対応済みアプリではフレンド対戦の高頻度ゲーム中同期をWebSocket優先にします。READY、部屋状態、決着保存などの重要な状態管理はRealtime Databaseに残します。

## 本番切り替え手順

1. Dropletで`pm2 status`と`curl https://realtime.hexagon.takutonkatsu.com/health`を確認します。
2. Realtime Databaseで`appConfig/realtimeTransport/url`が`wss://realtime.hexagon.takutonkatsu.com`であることを確認します。
3. まず`modes.friend=true`、`modes.ranked=false`、`receiveEnabled=true`でフレンド対戦だけ運用します。
4. フレンド対戦で数日、切断・再接続・不戦勝・リザルト表示・通信量を確認します。
5. ランク戦を導入する直前に`appConfig/maintenance/modes/ranked/enabled=true`で一時停止し、少人数でテストします。
6. 問題なければ`appConfig/realtimeTransport/modes/ranked=true`に変更し、最後にランク戦メンテナンスを解除します。

## 即時ロールバック

WebSocket側に異常が出た場合は、アプリの更新なしでRealtime Databaseから戻せます。

```json
{
  "enabled": true,
  "shadowEnabled": true,
  "receiveEnabled": false,
  "url": "wss://realtime.hexagon.takutonkatsu.com",
  "modes": {
    "friend": false,
    "ranked": false,
    "arena": false
  }
}
```

対戦自体も止める場合は、対象モードのメンテナンスをONにします。

```json
{
  "enabled": true,
  "title": "メンテナンス中",
  "message": "現在メンテナンス中です。完了までしばらくお待ちください。"
}
```

対象パス例:

- `appConfig/maintenance/modes/ranked`
- `appConfig/maintenance/modes/friend`
- `appConfig/maintenance/modes/endless`
- `appConfig/maintenance/modes/cpu`
- `appConfig/maintenance/modes/arena`
