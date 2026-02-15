import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions";
import {getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

/**
 * user_roomsコレクションのドキュメントが削除された時に、
 * そのroom_idに関連するmessagesコレクションのドキュメントも自動的に削除する
 */
export const cascadeDeleteRoom = onDocumentDeleted("user_rooms/{roomId}", async (event) => {
  const roomId = event.params.roomId;
  
  try {
    logger.info(`Room ${roomId} was deleted. Starting cascade delete of related messages.`);
    
    // 削除されたroomのuser_idを取得（削除前のデータ）
    const deletedRoomData = event.data?.data();
    if (!deletedRoomData) {
      logger.warn(`No data found for deleted room ${roomId}`);
      return;
    }
    
    const userId = deletedRoomData.user_id;
    
    // そのroom_idに関連するmessagesを検索して削除
    const messagesQuery = await db
      .collection("messages")
      .where("room_id", "==", roomId)
      .where("user_id", "==", userId)
      .get();
    
    if (messagesQuery.empty) {
      logger.info(`No messages found for room ${roomId}`);
      return;
    }
    
    // バッチ削除を実行
    const batch = db.batch();
    let deleteCount = 0;
    
    messagesQuery.docs.forEach((doc) => {
      batch.delete(doc.ref);
      deleteCount++;
    });
    
    await batch.commit();
    
    logger.info(`Successfully deleted ${deleteCount} messages for room ${roomId}`);
    
  } catch (error) {
    logger.error(`Error during cascade delete for room ${roomId}:`, error);
    throw error;
  }
}); 