// setAdmin.js
const admin = require('firebase-admin');

// 1) サービスアカウント JSON のパス
const serviceAccount = require('./serviceAccountKey.json');//ここはキーjsonの相対パス

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

// 2) 管理者にしたいユーザーの UID を指定
const targetUid = '7INz6EHAsZO6XoKBEdHpOEFty3y1';//cassia1417x@gmail.com

async function setAdminClaim() {
  try {
    await admin.auth().setCustomUserClaims(targetUid, { admin: true });
    console.log(`✅ UID=${targetUid} に admin=true を付与しました。`);
    process.exit(0);
  } catch (error) {
    console.error('❌ カスタムクレーム付与エラー:', error);
    process.exit(1);
  }
}

setAdminClaim();
