import {onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

/**
 * user_wordsのlist_idを文字列から配列に変換する
 * 空文字の場合は空の配列に、通常の文字列は単一要素の配列に変換
 */
export const deleteUnusedWordlists = onCall(async (request) => {
  try {
    // 認証されたユーザーのみアクセス可能
    if (!request.auth) {
      throw new Error("Authentication required");
    }

    const userId = request.auth.uid;
    logger.info(`Starting list_id migration for all users by: ${userId}`);

    // 全てのuser_wordsを取得
    const userWordsSnapshot = await db
      .collection("user_words")
      .get();

    // user_wordsのlist_idを文字列から配列に変換
    const migrationBatch = db.batch();
    let migrationCount = 0;
    
    userWordsSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      const listId = data.list_id as string | string[] | undefined;
      
      // 文字列の場合は配列に変換して保存
      if (typeof listId === "string") {
        const listIdArray = listId === "" ? [] : [listId];
        migrationBatch.update(doc.ref, {list_id: listIdArray});
        migrationCount++;
      }
    });
    
    // データ移行を実行
    if (migrationCount > 0) {
      await migrationBatch.commit();
      logger.info(`Migrated ${migrationCount} user_words from string to array`);
    }

    return {
      success: true,
      migratedCount: migrationCount,
      message: migrationCount > 0
        ? `${migrationCount}件のlist_idを配列に変換しました`
        : "変換する項目はありませんでした",
    };
  } catch (error) {
    logger.error("Error during list_id migration:", error);
    throw new Error(`list_id migration failed: ${error}`);
  }
});

