import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

const db = getFirestore();

interface SaveFCMTokenRequest {
  token: string;
}

/**
 * FCMトークンをFirestoreのusersコレクションに保存する関数
 * 認証されたユーザーのuidを使用してドキュメントを更新する
 */
export const saveFCMToken = onCall<SaveFCMTokenRequest>(
  {
    region: "asia-northeast1",
    cors: true,
  },
  async (request) => {
    try {
      // 認証チェック
      if (!request.auth) {
        logger.error("Unauthenticated request to saveFCMToken");
        throw new HttpsError("unauthenticated", "ユーザー認証が必要です");
      }

      const { token } = request.data;
      const uid = request.auth.uid;

      // トークンの検証
      if (!token || typeof token !== "string" || token.trim() === "") {
        logger.error(`Invalid FCM token provided: ${token}`);
        throw new HttpsError("invalid-argument", "有効なFCMトークンが必要です");
      }

      logger.info(`Saving FCM token for user: ${uid}`);

      // ユーザーの存在確認
      try {
        await getAuth().getUser(uid);
      } catch (error) {
        logger.error(`User ${uid} not found in Auth: ${error}`);
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }

      // FirestoreのusersコレクションにFCMトークンを保存
      await db.collection("users").doc(uid).set(
        {
          fcmToken: token.trim(),
          lastTokenUpdate: new Date(),
          tokenUpdatedBy: "client_app",
        },
        { merge: true }
      );

      logger.info(`FCM token saved successfully for user: ${uid}`);

      return {
        success: true,
        message: "FCMトークンが正常に保存されました",
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      logger.error("Error in saveFCMToken function:", error);

      // 既にHttpsErrorの場合はそのまま投げる
      if (error instanceof HttpsError) {
        throw error;
      }

      // その他のエラーは内部エラーとして扱う
      throw new HttpsError(
        "internal",
        "FCMトークンの保存中にエラーが発生しました"
      );
    }
  }
);
