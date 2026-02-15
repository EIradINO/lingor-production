import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {Storage} from "@google-cloud/storage";
import {VertexAI} from "@google-cloud/vertexai";
import * as logger from "firebase-functions/logger";

// Firebase Admin初期化
if (!admin.apps.length) {
  admin.initializeApp();
}

// Vertex AI設定
const vertex_ai = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT || "lingosavor",
  location: "us-central1",
});

const generativeModel = vertex_ai.preview.getGenerativeModel({
  model: "gemini-2.5-flash-lite"
});

// Cloud Storage クライアント
const storage = new Storage();

// 画像ファイル用のプロンプト生成関数
function generateImagePrompt(): string {
  return 'これらの画像に含まれるテキストを英語で文字起こししてください。改行は原則禁止です。';
}

// MIMEタイプを取得する関数
function getImageMimeType(fileName: string): string {
  const parts = fileName.split('.');
  const extension = parts[parts.length - 1].toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    default:
      return 'image/jpeg'; // デフォルトはjpeg
  }
}

export const transcribeImages = onCall(
  {
    timeoutSeconds: 540, // 9分のタイムアウト
  },
  async (request) => {
    try {
      const { data, auth } = request;
      
      // 認証済みユーザーかどうかを確認
      if (!auth) {
        throw new HttpsError(
          'unauthenticated',
          'この機能を利用するには認証が必要です。'
        );
      }

      const {documentId}: {documentId: string} = data;

      if (!documentId) {
        throw new HttpsError(
          'invalid-argument',
          'Document ID is required'
        );
      }

      logger.info(`Starting image transcription for document: ${documentId} for user: ${auth.uid}`);

      // Firestoreからドキュメント情報を取得
      const docRef = admin.firestore().collection("user_documents").doc(documentId);
      const docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        throw new HttpsError(
          'not-found',
          'Document not found'
        );
      }

      const docData = docSnapshot.data();
      if (!docData) {
        throw new HttpsError(
          'not-found',
          'Document data not found'
        );
      }

      const imagePaths = docData.image_paths; // 画像パスの配列
      const user_id = docData.user_id;

      // リクエストしたユーザーがドキュメントの所有者かチェック
      if (user_id !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'このドキュメントにアクセスする権限がありません。'
        );
      }

      if (!imagePaths || !Array.isArray(imagePaths) || imagePaths.length === 0) {
        throw new HttpsError(
          'failed-precondition',
          'No image paths found'
        );
      }

      logger.info(`Retrieved document info: user_id=${user_id}, image_count=${imagePaths.length}`);

      // プロンプトを生成
      const prompt = generateImagePrompt();

      // 各画像ファイルをダウンロードして処理用に準備
      const imageParts = [];
      
      for (let i = 0; i < imagePaths.length; i++) {
        const imagePath = imagePaths[i];
        logger.info(`Downloading image ${i + 1}/${imagePaths.length} from: ${imagePath}`);

        try {
          // GSパスからbucketとfilePathを抽出
          const pathParts = imagePath.replace('gs://', '').split('/');
          const bucketName = pathParts[0];
          const filePath = pathParts.slice(1).join('/');

          const bucket = storage.bucket(bucketName);
          const file = bucket.file(filePath);

          // ファイルの存在確認
          const [exists] = await file.exists();
          if (!exists) {
            logger.warn(`Image file not found: ${imagePath}`);
            continue;
          }

          // 画像ファイルをBufferとしてダウンロード
          const [fileContents] = await file.download();
          logger.info(`Downloaded image ${i + 1}, size: ${fileContents.length} bytes`);

          // ファイルサイズチェック（20MB制限）
          const maxFileSize = 20 * 1024 * 1024; // 20MB
          if (fileContents.length > maxFileSize) {
            logger.warn(`Image file too large: ${imagePath}`);
            continue;
          }

          // MIMEタイプを取得
          const fileName = filePath.split('/').pop() || 'image.jpg';
          const mimeType = getImageMimeType(fileName);

          // 画像をbase64エンコード
          const base64Image = Buffer.from(fileContents).toString('base64');

          imageParts.push({
            inlineData: {
              mimeType: mimeType,
              data: base64Image
            }
          });

        } catch (downloadError) {
          logger.error(`Error downloading image ${i + 1}:`, downloadError);
          continue; // エラーが発生した画像はスキップして続行
        }
      }

      if (imageParts.length === 0) {
        throw new HttpsError(
          'failed-precondition',
          'No valid images found for processing'
        );
      }

      logger.info(`Processing ${imageParts.length} images with Gemini`);

      try {
        // Geminiで複数画像を一度に処理
        const result = await generativeModel.generateContent({
          contents: [
            {
              role: 'user',
              parts: [
                {
                  text: prompt
                },
                ...imageParts
              ]
            }
          ]
        });

        const transcribedText = result.response.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!transcribedText) {
          throw new HttpsError(
            'internal',
            'No transcription generated for images'
          );
        }

        logger.info(`Image transcription completed. Length: ${transcribedText.length} characters`);

        // 文字起こし結果をFirestoreに保存
        await docRef.update({
          transcription: transcribedText
        });

        return {
          success: true,
          documentId: documentId,
          transcription: transcribedText,
          processedImages: imageParts.length
        };

      } catch (aiError) {
        logger.error('Error transcribing images:', aiError);
        throw new HttpsError(
          'internal',
          `Failed to transcribe images: ${aiError instanceof Error ? aiError.message : 'Unknown AI error'}`
        );
      }

    } catch (error) {
      logger.error("Error in transcribeImages function:", error);
      
      // FirebaseFunctionsのエラーが既に投げられている場合はそのまま再スロー
      if (error instanceof HttpsError) {
        throw error;
      }
      
      throw new HttpsError(
        'internal',
        `Internal server error: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }
); 