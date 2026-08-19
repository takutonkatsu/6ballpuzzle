#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');
const serviceAccount = require('/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json');

const APPLY = process.argv.includes('--apply');
const DATABASE_URL =
  'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';

const NOTICE_ID = 'large_update_coming_2026_08_19';

const notice = {
  enabled: true,
  title: '大型アップデート近日公開！',
  message:
    'いつもヘキサゴンを遊んでいただきありがとうございます。\n\n' +
    'ヘキサゴンの大型アップデートを近日公開予定です。\n' +
    'コレクション、ショップ、フレンド機能、演出まわりなど、ゲーム全体をより楽しく遊べるように大きく調整しています。\n\n' +
    'もうまもなく配信予定ですので、ぜひ楽しみにお待ちください。\n' +
    '今後ともヘキサゴンをよろしくお願いいたします。',
  platforms: ['all'],
  minBuild: 0,
  publishedAt: new Date().toISOString(),
};

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: DATABASE_URL,
    });
  }

  const updates = {
    'appConfig/notices': {
      [NOTICE_ID]: notice,
    },
    'appConfig/notice': null,
  };

  console.log(
    JSON.stringify(
      {
        apply: APPLY,
        noticeId: NOTICE_ID,
        updates,
      },
      null,
      2,
    ),
  );

  if (!APPLY) {
    console.log(
      '\nDRY RUN ONLY. Apply with: node tools/publish_large_update_notice.js --apply',
    );
    return;
  }

  await admin.database().ref().update(updates);
  console.log('Published large update notice and replaced global notices.');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
