import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { createBulkNotifications } from './send-notification';

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

/**
 * 毎日19時に全ユーザーに一斉通知を送信するスケジューラー関数
 */
export const sendDailyNotification = onSchedule({
  schedule: '0 19 * * *', // 毎日19時（日本時間）
  timeZone: 'Asia/Tokyo',
  memory: '512MiB',
  timeoutSeconds: 540, // 9分
}, async () => {
  const now = new Date().toISOString();
  logger.info('🔔 Daily notification started', { timestamp: now });

  try {
    // 全ユーザーを取得
    const allUsersSnapshot = await db.collection('users').get();

    if (allUsersSnapshot.empty) {
      logger.info('📭 No users found for daily notification');
      return;
    }

    logger.info(`📊 Sending daily notifications to ${allUsersSnapshot.size} users`);

    // 全ユーザーIDを抽出
    const allUserIds = allUsersSnapshot.docs.map(doc => doc.id);

    // 暫定的な通知内容（後で変更可能）
    const title = '今日はどんな英語を学びましたか？☺️';
    const body = '読んだり📖聴いたり🎧した英語をLingoSavorで振り返ろう！';
    
    // 共通関数を使って通知を一括作成
    const notificationIds = await createBulkNotifications(
      allUserIds,
      title,
      body,
      {
        screen: 'document',
        additionalData: {},
      }
    );

    logger.info('✅ Daily notifications sent successfully', {
      notificationsSent: notificationIds.length,
      totalUsers: allUsersSnapshot.size,
    });

    return;
  } catch (error) {
    logger.error('❌ Failed to send daily notifications', error);
    throw error;
  }
});

/**
 * 毎日23時に単語リストがあるユーザーにリマインダーを送信するスケジューラー関数
 */
export const sendWordListReminder = onSchedule({
  schedule: '0 23 * * *', // 毎日23時（日本時間）
  timeZone: 'Asia/Tokyo',
  memory: '512MiB',
  timeoutSeconds: 540, // 9分
}, async () => {
  const now = new Date().toISOString();
  logger.info('📚 Word list reminder started', { timestamp: now });

  try {
    // word_listフィールドがあるuser_tasksを取得
    const userTasksSnapshot = await db.collection('user_tasks')
      .where('word_list', '!=', null)
      .get();

    if (userTasksSnapshot.empty) {
      logger.info('📭 No users with word lists found');
      return;
    }

    logger.info(`📊 Found ${userTasksSnapshot.size} users with word lists`);

    // ユーザーごとに通知を作成（カスタマイズが必要なため個別処理）
    const notificationPromises = userTasksSnapshot.docs.map(async (doc) => {
      const data = doc.data();
      const userId = data.userId;
      const wordList = data.word_list || [];

      // 最大5個の単語を取得
      const wordsToShow = wordList.slice(0, 5).map((item: any) => item.word);
      
      if (wordsToShow.length === 0) {
        logger.info(`⚠️ User ${userId} has empty word list, skipping`);
        return null;
      }

      // 単語をカンマ区切りで表示
      const wordString = wordsToShow.join(', ');
      const body = `${wordString}...意味を言えますか？`;

      // 個別に通知を作成（Firestoreに直接追加）
      try {
        await db.collection('notifications').add({
          userId: userId,
          title: '忘れかけている単語があります‼️',
          body: body,
          screen: 'home',
          data: {},
          createdAt: FieldValue.serverTimestamp(),
          createdBy: 'system',
          status: 'pending',
        });
        return userId;
      } catch (error) {
        logger.error(`Failed to create notification for user ${userId}`, error);
        return null;
      }
    });

    const results = await Promise.all(notificationPromises);
    const successCount = results.filter(r => r !== null).length;

    logger.info('✅ Word list reminders sent successfully', {
      notificationsSent: successCount,
      totalUsers: userTasksSnapshot.size,
    });

    return;
  } catch (error) {
    logger.error('❌ Failed to send word list reminders', error);
    throw error;
  }
});

/**
 * 毎日7時に前日の復習問題があるユーザーにリマインダーを送信するスケジューラー関数
 */
export const sendReviewReminder = onSchedule({
  schedule: '0 7 * * *', // 毎日7時（日本時間）
  timeZone: 'Asia/Tokyo',
  memory: '512MiB',
  timeoutSeconds: 540, // 9分
}, async () => {
  const now = new Date();
  logger.info('📝 Review reminder started', { timestamp: now.toISOString() });

  try {
    // 昨日の日付を取得（YYYY-MM-DD形式）
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayString = yesterday.toISOString().split('T')[0]; // 'YYYY-MM-DD'

    logger.info(`🗓️ Looking for tasks with date: ${yesterdayString}`);

    // 昨日の日付のuser_tasksを取得
    const userTasksSnapshot = await db.collection('user_tasks')
      .where('date', '==', yesterdayString)
      .get();

    if (userTasksSnapshot.empty) {
      logger.info('📭 No tasks found for yesterday');
      return;
    }

    logger.info(`📊 Found ${userTasksSnapshot.size} tasks from yesterday`);

    // ユーザーIDを抽出（重複を排除）
    const userIds = [...new Set(userTasksSnapshot.docs.map(doc => doc.data().user_id))];

    logger.info(`👥 Sending review reminders to ${userIds.length} unique users`);

    // 一括で通知を作成
    const notificationIds = await createBulkNotifications(
      userIds,
      'あなたのためだけの復習問題が届いています',
      '毎日解いて英語力を爆上げしよう！',
      {
        screen: 'home',
        additionalData: {},
      }
    );

    logger.info('✅ Review reminders sent successfully', {
      notificationsSent: notificationIds.length,
      totalUsers: userIds.length,
      yesterdayDate: yesterdayString,
    });

    return;
  } catch (error) {
    logger.error('❌ Failed to send review reminders', error);
    throw error;
  }
});

