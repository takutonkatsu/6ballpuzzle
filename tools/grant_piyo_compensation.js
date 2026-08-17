#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');
const serviceAccount = require('/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json');

const APPLY = process.argv.includes('--apply');
const DATABASE_URL =
  'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';

const UID = 'dprGBMQfeuU6eFWL3xo4mpTi5x82';
const PUBLIC_ID = 'WVD8J9';
const DISPLAY_NAME = 'ぴよ';
const GRANT_ID = 'compensation_piyo_2026_08_14_daily_win_and_ranked_s2';
const TOTAL_COINS = 220000;

const DAILY_WIN_BREAKDOWN = [
  {date: '2026-08-05', rank: 1, wins: 66, coins: 50000},
  {date: '2026-08-06', rank: 1, wins: 100, coins: 50000},
  {date: '2026-08-07', rank: 8, wins: 24, coins: 5000},
  {date: '2026-08-11', rank: 5, wins: 23, coins: 5000},
  {date: '2026-08-12', rank: 8, wins: 23, coins: 5000},
  {date: '2026-08-13', rank: 10, wins: 13, coins: 5000},
];

const RANKED_SEASON_COMPENSATION_COINS = 100000;

function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: DATABASE_URL,
    });
  }

  const dailyTotal = DAILY_WIN_BREAKDOWN.reduce((sum, row) => sum + row.coins, 0);
  const grant = {
    type: 'compensation',
    title: 'ランキング報酬補填',
    message:
      '今日の勝利数ランキング報酬の未付与分と、シーズン2のランク戦記録不具合のお詫びとして、220,000コインを補填いたしました。ご迷惑をおかけし申し訳ございません。',
    coins: TOTAL_COINS,
    playerName: DISPLAY_NAME,
    publicId: PUBLIC_ID,
    reason: 'daily_win_rewards_and_ranked_2026_07_missing_record',
    dailyWinRewardCoins: dailyTotal,
    rankedSeasonCompensationCoins: RANKED_SEASON_COMPENSATION_COINS,
    dailyWinBreakdown: DAILY_WIN_BREAKDOWN,
    createdAt: admin.database.ServerValue.TIMESTAMP,
  };

  const updates = {
    [`adminGrants/${UID}/${GRANT_ID}`]: grant,
  };

  console.log(JSON.stringify({
    apply: APPLY,
    uid: UID,
    publicId: PUBLIC_ID,
    displayName: DISPLAY_NAME,
    grantId: GRANT_ID,
    totalCoins: TOTAL_COINS,
    dailyWinRewardCoins: dailyTotal,
    rankedSeasonCompensationCoins: RANKED_SEASON_COMPENSATION_COINS,
    updates,
  }, null, 2));

  if (!APPLY) {
    console.log('\nDRY RUN ONLY. Apply with: node tools/grant_piyo_compensation.js --apply');
    return Promise.resolve();
  }

  return admin.database().ref().update(updates).then(() => {
    console.log('Applied compensation grant.');
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
