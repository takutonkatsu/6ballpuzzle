# Realtime Production Checklist

## 配信前

- `https://realtime.hexagon.takutonkatsu.com/health` が `ok: true` を返す。
- Droplet再起動後に `pm2 status` で `hexagon-realtime` が自動起動している。
- `pm2 logs hexagon-realtime --lines 100` に継続的なエラーがない。
- `certbot renew --dry-run` が成功する。
- Realtime Database の `appConfig/realtimeTransport/url` が `wss://realtime.hexagon.takutonkatsu.com` になっている。
- リリースビルドで `ws://` が使われていない。
- `appConfig/realtimeTransport/modes.ranked` はランク戦導入直前まで `false` にする。

## フレンド対戦で確認する項目

- 操作ボールの左右移動、回転、ハードドロップが相手描画で大きくズレない。
- 自然接地時に操作ボールが二重に落下しない。
- 妨害ボールが復帰後にも正しく降る。
- 10秒以上の通信断で、切断側は不戦敗、相手側は不戦勝になる。
- リザルト画面とレコード画面に不戦勝/不戦敗が正しく残る。
- ホームへ戻るボタンが反応する。

## ランク戦導入手順

1. `appConfig/maintenance/modes/ranked/enabled=true` にしてマッチングを止める。
2. `appConfig/realtimeTransport/modes.ranked=true` にする。
3. 少人数で実機テストする。
4. レート増減、ランキング反映、対戦履歴、レコード表示を確認する。
5. 問題がなければ `appConfig/maintenance/modes/ranked/enabled=false` にする。

## 異常時の戻し方

- WebSocket同期だけ戻す: `appConfig/realtimeTransport/receiveEnabled=false`
- 対象モードだけ止める: `appConfig/maintenance/modes/{mode}/enabled=true`
- 全体停止する: `appConfig/maintenance/global/enabled=true`

## 通信量確認

`METRICS_TOKEN` を設定している場合のみ、次で直近の集計を確認する。

```bash
curl "https://realtime.hexagon.takutonkatsu.com/metrics?token=YOUR_TOKEN"
```

目安として、現在のフレンド対戦1試合は約120KB前後。ランク戦導入後は、対人戦数に比例してDroplet側の転送量が増える。
