import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

// Firebase Admin初期化（既に初期化されている場合はスキップ）
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();
const messaging = getMessaging();

interface NotificationData {
  userId: string;
  title: string;
  body: string;
  screen?: string;
  data?: { [key: string]: string };
}

interface SendNotificationRequest {
  userId: string;
  title: string;
  body: string;
  screen?: string;
  additionalData?: { [key: string]: string };
}

interface SendBulkNotificationRequest {
  userIds: string[];
  title: string;
  body: string;
  screen?: string;
  additionalData?: { [key: string]: string };
}

/**
 * 複数ユーザーに通知ドキュメントを一括作成する内部関数
 * sendBulkNotificationや他のCloud Functionsから呼び出し可能
 */
export async function createBulkNotifications(
  userIds: string[],
  title: string,
  body: string,
  options?: {
    screen?: string;
    additionalData?: { [key: string]: string };
    createdBy?: string;
  }
): Promise<string[]> {
  const BATCH_SIZE = 100;
  const notificationIds: string[] = [];
  const totalBatches = Math.ceil(userIds.length / BATCH_SIZE);
  let successfulBatches = 0;
  let failedBatches = 0;

  logger.info(`Starting bulk notification for ${userIds.length} users in ${totalBatches} batches`);

  // 100件ずつに分けて処理
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batchUserIds = userIds.slice(i, i + BATCH_SIZE);
    const batchNumber = Math.floor(i / BATCH_SIZE) + 1;
    
    logger.info(`Processing batch ${batchNumber}/${totalBatches} (${batchUserIds.length} users)`);

    try {
      const batch = db.batch();
      const batchNotificationIds: string[] = [];

      // 各ユーザー向けの通知ドキュメントを作成
      for (const userId of batchUserIds) {
        const notificationRef = db.collection('notifications').doc();

        batch.set(notificationRef, {
          userId: userId,
          title: title,
          body: body,
          screen: options?.screen || null,
          data: options?.additionalData || {},
          createdAt: FieldValue.serverTimestamp(),
          createdBy: options?.createdBy || 'system',
          status: 'pending',
        });

        batchNotificationIds.push(notificationRef.id);
      }

      await batch.commit();
      
      // 成功したらIDを追加
      notificationIds.push(...batchNotificationIds);
      successfulBatches++;
      
      logger.info(`✅ Batch ${batchNumber}/${totalBatches} committed successfully (${batchUserIds.length} notifications)`);
    } catch (error) {
      failedBatches++;
      logger.error(`❌ Batch ${batchNumber}/${totalBatches} failed`, {
        error: error instanceof Error ? error.message : String(error),
        batchSize: batchUserIds.length,
        batchUserIds: batchUserIds,
        batchNumber,
      });
      // エラーを記録するが、次のバッチは続行
    }

    // バッチ間で少し待機（レート制限対策）
    if (i + BATCH_SIZE < userIds.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }

  logger.info(`Bulk notification completed: ${notificationIds.length}/${userIds.length} notifications queued`, {
    successfulBatches,
    failedBatches,
    totalBatches,
    successRate: `${((successfulBatches / totalBatches) * 100).toFixed(2)}%`,
  });

  return notificationIds;
}

/**
 * 特定のユーザーにプッシュ通知を送信する関数
 * Firestore の 'notifications' コレクションにドキュメントが追加されたときにトリガーされる
 */
export const sendPushNotification = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    try {
      const snap = event.data;
      if (!snap) {
        logger.error('No data associated with the event');
        return;
      }

      // 1. 追加されたドキュメントのデータを取得
      const newData = snap.data() as NotificationData;
      const { userId, title, body, screen, data } = newData;

      if (!userId || !title || !body) {
        logger.error('Missing required fields: userId, title, or body');
        return;
      }

      logger.info(`Sending notification to user: ${userId}`);
      logger.info(`Title: ${title}, Body: ${body}`);

      // 2. ユーザーIDからFCMトークンを取得
      const userDoc = await db.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        logger.error(`User ${userId} not found.`);
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;

      if (!fcmToken) {
        logger.error(`FCM token for user ${userId} not found.`);
        return;
      }

      // 3. 通知メッセージのペイロードを作成
      const messageData: { [key: string]: string } = {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        notificationId: event.params.notificationId,
        ...data,
      };

      if (screen) {
        messageData.screen = screen;
      }

      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: body,
        },
        // iOS向けの細かい設定
        apns: {
          payload: {
            aps: {
              sound: 'default', // 通知音
              badge: 1, // バッジ数
              alert: {
                title: title,
                body: body,
              },
            },
          },
        },
        // Android向けの設定
        android: {
          notification: {
            title: title,
            body: body,
            sound: 'default',
            priority: 'high' as const,
            channelId: 'default_channel',
          },
        },
        // データペイロード
        data: messageData,
      };

      // 4. FCM経由でメッセージを送信
      const response = await messaging.send(message);
      logger.info('Successfully sent message:', response);

      // 5. 送信完了後、通知ドキュメントを更新
      await snap.ref.update({
        sentAt: FieldValue.serverTimestamp(),
        messageId: response,
        status: 'sent',
      });
    } catch (error) {
      logger.error('Error sending message:', error);

      // エラー情報をドキュメントに記録
      if (event.data) {
        await event.data.ref.update({
          status: 'failed',
          error: error instanceof Error ? error.message : String(error),
          failedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }
);

/**
 * 手動で通知を送信するためのHTTPS関数
 * 例: テストや管理画面からの通知送信
 */
export const sendNotificationManual = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  const data = request.data as SendNotificationRequest;
  const { userId, title, body, screen, additionalData } = data;

  if (!userId || !title || !body) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: userId, title, or body'
    );
  }

  try {
    // Firestoreの notifications コレクションにドキュメントを追加
    // これにより sendPushNotification 関数がトリガーされる
    const notificationRef = await db.collection('notifications').add({
      userId: userId,
      title: title,
      body: body,
      screen: screen || null,
      data: additionalData || {},
      createdAt: FieldValue.serverTimestamp(),
      createdBy: request.auth.uid,
      status: 'pending',
    });

    return {
      success: true,
      notificationId: notificationRef.id,
      message: 'Notification queued successfully',
    };
  } catch (error) {
    logger.error('Error creating notification:', error);
    throw new HttpsError('internal', 'Failed to create notification');
  }
});

/**
 * 複数ユーザーに一括で通知を送信する関数
 * 大量送信の場合は100件ずつのバッチに分けて処理
 */
export const sendBulkNotification = onCall(
  {
    timeoutSeconds: 540,  // 9分（最大値）
    memory: '1GiB',       // 1GB
  },
  async (request) => {
  // 認証チェック（管理者権限が必要）
  if (!request.auth) {
    throw new HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  const data = request.data as SendBulkNotificationRequest;
  const { userIds, title, body, screen, additionalData } = data;

  if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
    throw new HttpsError(
      'invalid-argument',
      'userIds must be a non-empty array'
    );
  }

  if (!title || !body) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: title or body'
    );
  }

  try {
    const notificationIds = await createBulkNotifications(
      userIds,
      title,
      body,
      {
        screen: screen,
        additionalData: additionalData,
        createdBy: request.auth.uid,
      }
    );

    const totalBatches = Math.ceil(userIds.length / 100);

    return {
      success: true,
      notificationIds: notificationIds,
      totalBatches: totalBatches,
      message: `${userIds.length} notifications queued successfully in ${totalBatches} batches`,
    };
  } catch (error) {
    logger.error('Error creating bulk notifications:', error);
    throw new HttpsError('internal', 'Failed to create bulk notifications');
  }
});