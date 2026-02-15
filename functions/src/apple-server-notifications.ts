import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

// admin.initializeApp() は index.ts で一度だけ呼ぶのが推奨ですが、
// ここで呼んでも二重初期化にはなりません（ガードされているため）
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * App Store Server Notifications V2を受け取るHTTPSエンドポイント（Gen2対応）
 */
export const appleServerNotifications = onRequest(async (req, res) => {
  logger.info("=== Apple Server Notifications Endpoint Called ===");
  logger.info("Request method:", req.method);
  logger.info("Request headers:", JSON.stringify(req.headers, null, 2));
  logger.info("Request body:", JSON.stringify(req.body, null, 2));
  
  if (req.method !== "POST") {
    logger.warn("Invalid request method:", req.method);
    res.status(405).send("Method Not Allowed");
    return;
  }
  
  try {
    const signedPayload = req.body.signedPayload;
    logger.info("Received signedPayload:", signedPayload);
    
    if (!signedPayload) {
      logger.warn("No signedPayload found in request body");
      res.status(200).send("No signedPayload");
      return;
    }
    
    // 基本的なペイロードの構造をログ出力
    logger.info("Payload structure:", {
      hasSignedPayload: !!signedPayload,
      payloadLength: signedPayload ? signedPayload.length : 0,
      payloadType: typeof signedPayload
    });
    
    logger.info("=== Processing completed successfully ===");
    res.status(200).send("OK");
  } catch (error) {
    logger.error("Error processing App Store notification:", error);
    logger.error("Error details:", {
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined
    });
    res.status(200).send("Error logged");
  }
});
