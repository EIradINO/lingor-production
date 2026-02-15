import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import { createBulkNotifications } from './send-notification';

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

export const addMonthlyFreeGems = onSchedule({
  schedule: '0 0 1 * *',
  timeZone: 'Asia/Tokyo',
  memory: '256MiB',
  timeoutSeconds: 300,
}, async () => {
  const now = new Date().toISOString();
  logger.info('🚀 Monthly free gems grant started', { timestamp: now });

  try {
    const snapshot = await db.collection('users').where('plan', '==', 'free').get();

    if (snapshot.empty) {
      logger.info('📭 No users with plan == "free"');
      return;
    }

    logger.info(`📊 Targeting ${snapshot.size} users (plan == 'free')`);

    let processedCount = 0;
    let batchesCommitted = 0;
    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        gems: admin.firestore.FieldValue.increment(100),
        gems_updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      processedCount += 1;
      opsInBatch += 1;

      if (opsInBatch === 500) {
        await batch.commit();
        batchesCommitted += 1;
        batch = db.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
      batchesCommitted += 1;
    }

    logger.info('✅ Monthly free gems grant completed', {
      processedCount,
      batchesCommitted,
    });

    // 全ユーザーに通知を送信
    logger.info('🔔 Starting to send notifications to all users');
    
    try {
      // 全ユーザーを取得
      const allUsersSnapshot = await db.collection('users').get();
      
      if (allUsersSnapshot.empty) {
        logger.info('📭 No users found for notifications');
        return;
      }

      logger.info(`📊 Sending notifications to ${allUsersSnapshot.size} users`);

      // 全ユーザーIDを抽出
      const allUserIds = allUsersSnapshot.docs.map(doc => doc.id);

      // 共通関数を使って通知を一括作成
      const notificationIds = await createBulkNotifications(
        allUserIds,
        'GEMが追加されました',
        '毎月1日はGEM配布日！LingoSavorで効率的に英語を学ぼう！',
        {
          screen: 'document',
          additionalData: {},
        }
      );

      logger.info('✅ Notifications sent successfully', {
        notificationsSent: notificationIds.length,
      });
    } catch (notificationError) {
      logger.error('❌ Failed to send notifications', notificationError);
      // 通知送信が失敗してもgem配布は成功しているので、エラーをthrowしない
    }

    return;
  } catch (error) {
    logger.error('❌ Failed to grant monthly free gems', error);
    throw error;
  }
});