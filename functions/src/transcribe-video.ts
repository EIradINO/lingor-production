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

// 動画ファイル用のプロンプト生成関数
function generateVideoPrompt(): string {
  return `この動画ファイルの音声内容を英語で文字起こししてください。

重要な指示：
- 動画の音声部分のみを文字起こししてください
- すべての音声内容を正確に文字起こししてください
- 話者が変わる場合は適切に段落を分けてください
- 自然な文章として読みやすい形式で整理してください
- 動画の視覚的な内容については言及しないでください
`;
}

// MIMEタイプを取得する関数
function getMimeType(fileName: string): string {
  const parts = fileName.split('.');
  const extension = parts[parts.length - 1].toLowerCase();
  switch (extension) {
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'mpg':
    case 'mpeg':
      return 'video/mpeg';
    default:
      return 'video/mp4'; // デフォルトはmp4
  }
}

export const transcribeVideo = onCall(
  {
    timeoutSeconds: 300, // 5分のタイムアウト（動画は処理時間が長いため）
    memory: '1GiB',
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

      logger.info(`Starting video transcription for document: ${documentId} for user: ${auth.uid}`);

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

      const path = docData.path;
      const user_id = docData.user_id;
      const fileName = docData.file_name;

      // リクエストしたユーザーがドキュメントの所有者かチェック
      if (user_id !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'このドキュメントにアクセスする権限がありません。'
        );
      }

      if (!path) {
        throw new HttpsError(
          'failed-precondition',
          'Document path missing'
        );
      }

      logger.info(`Retrieved document info: path=${path}, user_id=${user_id}, fileName=${fileName}`);

      // Cloud Storageから動画ファイルをダウンロード
      const gsUrl = path;
      logger.info(`Downloading video file from: ${gsUrl}`);

      // GSパスからbucketとfilePathを抽出
      const pathParts = gsUrl.replace('gs://', '').split('/');
      const bucketName = pathParts[0];
      const filePath = pathParts.slice(1).join('/');

      const bucket = storage.bucket(bucketName);
      const file = bucket.file(filePath);

      // ファイルの存在確認
      const [exists] = await file.exists();
      if (!exists) {
        throw new HttpsError(
          'not-found',
          'Video file not found in storage'
        );
      }

      // 動画ファイルをBufferとしてダウンロード
      const [fileContents] = await file.download();
      logger.info(`Downloaded video file, size: ${fileContents.length} bytes`);

      // ファイルサイズチェック（50MB制限 - 動画は音声より大きいため）
      const maxFileSize = 50 * 1024 * 1024; // 50MB
      if (fileContents.length > maxFileSize) {
        throw new HttpsError(
          'invalid-argument',
          'Video file too large. Maximum size is 50MB.'
        );
      }

      // プロンプトを生成
      const prompt = generateVideoPrompt();

      // MIMEタイプを取得
      const mimeType = getMimeType(fileName || 'video.mp4');

      try {
        // 動画ファイルをbase64エンコード
        const base64Video = Buffer.from(fileContents).toString('base64');

        logger.info(`Processing video file with MIME type: ${mimeType}`);

        const result = await generativeModel.generateContent({
          contents: [
            {
              role: 'user',
              parts: [
                {
                  text: prompt
                },
                {
                  inlineData: {
                    mimeType: mimeType,
                    data: base64Video
                  }
                }
              ]
            }
          ]
        });

        const transcribedText = result.response.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!transcribedText) {
          throw new HttpsError(
            'internal',
            'No transcription generated for video file'
          );
        }

        logger.info(`Video transcription completed. Length: ${transcribedText.length} characters`);

        // 文字起こし結果をFirestoreに保存
        await docRef.update({
          transcription: transcribedText
        });

        return {
          success: true,
          documentId: documentId,
          transcription: transcribedText
        };

      } catch (aiError) {
        logger.error('Error transcribing video:', aiError);
        throw new HttpsError(
          'internal',
          `Failed to transcribe video file: ${aiError instanceof Error ? aiError.message : 'Unknown AI error'}`
        );
      }

    } catch (error) {
      logger.error("Error in transcribeVideo function:", error);
      
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
