import {onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";

const db = getFirestore();
const auth = getAuth();

/**
 * ユーザーアカウントを完全に削除する
 * - Firebase Authenticationからユーザーを削除
 * - Firestoreから関連するすべてのデータを削除
 */
export const deleteAccount = onCall(async (request) => {
  try {
    // 認証されたユーザーのみアクセス可能
    if (!request.auth) {
      throw new Error("Authentication required");
    }

    const userId = request.auth.uid;
    logger.info(`Starting account deletion for user: ${userId}`);

    // 削除するコレクションとクエリ条件を定義
    const collectionsToDelete = [
      { collection: "messages", field: "user_id" },
      { collection: "user_documents", field: "user_id" },
      { collection: "user_rooms", field: "user_id" },
      { collection: "words", field: "user_id" },
      { collection: "user_wordlists", field: "user_id" },
      { collection: "users", field: "user_id" },
      { collection: "documents_savor_results", field: "user_id" },
      { collection: "messages", field: "user_id" },
      { collection: "user_words", field: "user_id" },
    ];

    let totalDeleted = 0;

    // 各コレクションからユーザーに関連するドキュメントを削除
    for (const item of collectionsToDelete) {
      try {
        const querySnapshot = await db
          .collection(item.collection)
          .where(item.field, "==", userId)
          .get();

        if (!querySnapshot.empty) {
          const batch = db.batch();
          let batchCount = 0;

          querySnapshot.docs.forEach((doc) => {
            batch.delete(doc.ref);
            batchCount++;
          });

          await batch.commit();
          totalDeleted += batchCount;
          
          logger.info(`Deleted ${batchCount} documents from ${item.collection}`);
        } else {
          logger.info(`No documents found in ${item.collection} for user ${userId}`);
        }
      } catch (error) {
        logger.error(`Error deleting from ${item.collection}:`, error);
        // エラーが発生してもスキップして他のコレクションも削除を試行
      }
    }

    // Firebase Authenticationからユーザーを削除
    try {
      await auth.deleteUser(userId);
      logger.info(`Successfully deleted user ${userId} from Authentication`);
    } catch (error) {
      logger.error(`Error deleting user from Authentication:`, error);
      throw new Error("Failed to delete user from Authentication");
    }

    logger.info(`Account deletion completed for user ${userId}. Total documents deleted: ${totalDeleted}`);
    
    return {
      success: true,
      message: "Account successfully deleted",
      documentsDeleted: totalDeleted
    };

  } catch (error) {
    logger.error("Error during account deletion:", error);
    throw new Error(`Account deletion failed: ${error}`);
  }
}); 