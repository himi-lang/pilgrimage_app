// setAdmin.js  — holy-land-pilgrimage-app をこの鍵で操作
const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});
const defaultUid = 'Ws4HzdmmVBf0352o62Xtu2dB2gw2'; // 必要なら差し替え
const targetUid = process.argv[2] || process.env.TARGET_UID || defaultUid;

(async () => {
  try {
    console.log('projectId:', admin.app().options.projectId); // 確認ログ
    const user = await admin.auth().getUser(targetUid);
    const claims = { ...(user.customClaims || {}), admin: true };
    await admin.auth().setCustomUserClaims(targetUid, claims);
    console.log(`✅ UID=${targetUid} に admin=true を付与しました。`);
    console.log('ℹ️ クライアントは再ログイン or getIdToken(true) で反映されます。');
    await admin.app().delete();
  } catch (e) {
    console.error('❌ カスタムクレーム付与エラー:', e);
    try { await admin.app().delete(); } catch {}
    process.exit(1);
  }
})();
