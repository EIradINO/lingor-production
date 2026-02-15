import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {Storage} from "@google-cloud/storage";
import {VertexAI} from "@google-cloud/vertexai";
import {PDFDocument, PDFPage} from "pdf-lib";
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
  model: "gemini-2.5-flash-lite",
  generationConfig: {
    temperature: 0,
  }
});

// Cloud Storage クライアント
const storage = new Storage();

// PDFを2ページごとに分割する関数
async function splitPdfByPages(pdfBytes: Uint8Array): Promise<Uint8Array[]> {
  const pdfDoc = await PDFDocument.load(pdfBytes);
  const totalPages = pdfDoc.getPageCount();
  const chunks: Uint8Array[] = [];

  for (let i = 0; i < totalPages; i += 2) {
    const newPdf = await PDFDocument.create();
    
    // 2ページを取得（最後のチャンクは1ページの場合もある）
    const pagesToCopy = [];
    pagesToCopy.push(i);
    if (i + 1 < totalPages) {
      pagesToCopy.push(i + 1);
    }

    const copiedPages = await newPdf.copyPages(pdfDoc, pagesToCopy);
    copiedPages.forEach((page: PDFPage) => newPdf.addPage(page));

    const pdfChunkBytes = await newPdf.save();
    chunks.push(pdfChunkBytes);
  }

  return chunks;
}

// プロンプト生成関数
function generatePrompt(transcriptionType: string): string {
  if (transcriptionType === "main") {
    return `このPDFページの英文を正確に英語で文字起こししてください。
メインの文章部分のみに焦点を当て、ヘッダー、フッター、ページ番号、目次、参考文献などの補助的な情報は除外してください。改行は原則禁止です。`;
  } else {
    return `このPDFページの内容を完全に文字起こししてください。
すべての情報（ヘッダー、フッター、ページ番号、目次、参考文献等も含む）を保持してください。改行は原則禁止です。`;
  }
}

export const transcribeDocument = onCall(
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

      logger.info(`Starting transcription for document: ${documentId} for user: ${auth.uid}`);

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
      const requestType = docData.request;

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

      // 文字起こし種類の確認（デフォルトはwhole）
      const transcriptionType = requestType || "whole";
      logger.info(`Retrieved document info: path=${path}, user_id=${user_id}, transcription_type=${transcriptionType}`);

      // Cloud StorageからPDFファイルをダウンロード
      const gsUrl = path;
      logger.info(`Downloading file from: ${gsUrl}`);

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
          'PDF file not found in storage'
        );
      }

      // PDFファイルをBufferとしてダウンロード
      const [fileContents] = await file.download();
      logger.info(`Downloaded file, size: ${fileContents.length} bytes`);

      // PDFを2ページごとに分割
      let pdfChunks: Uint8Array[];
      try {
        pdfChunks = await splitPdfByPages(fileContents);
        logger.info(`Split PDF into ${pdfChunks.length} chunks (2 pages each)`);
      } catch (pdfError) {
        logger.error("Error splitting PDF:", pdfError);
        throw new HttpsError(
          'internal',
          'Failed to split PDF file'
        );
      }

      // プロンプトを生成
      const prompt = generatePrompt(transcriptionType);

      // 各PDFチャンクをGeminiで文字起こし
      const transcribedChunks: string[] = [];
      
      for (let i = 0; i < pdfChunks.length; i++) {
        const pdfChunk = pdfChunks[i];
        logger.info(`Processing PDF chunk ${i + 1}/${pdfChunks.length}`);

        try {
          // PDFをbase64エンコード
          const base64Pdf = Buffer.from(pdfChunk).toString('base64');

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
                      mimeType: 'application/pdf',
                      data: base64Pdf
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
              `No transcription generated for chunk ${i + 1}`
            );
          }

          transcribedChunks.push(transcribedText);
          logger.info(`Completed chunk ${i + 1}/${pdfChunks.length}`);

        } catch (aiError) {
          logger.error(`Error transcribing chunk ${i + 1}:`, aiError);
          throw new HttpsError(
            'internal',
            `Failed to transcribe chunk ${i + 1}: ${aiError instanceof Error ? aiError.message : 'Unknown error'}`
          );
        }
      }

      // 全チャンクの結果を結合
      const finalTranscription = transcribedChunks.join('\n\n');
      logger.info(`Transcription completed. Final length: ${finalTranscription.length} characters`);

      // 文字起こし結果をFirestoreに保存（transcriptionのみ）
      await docRef.update({
        transcription: finalTranscription
      });

      return {
        success: true,
        documentId: documentId,
        transcription: finalTranscription
      };

    } catch (error) {
      logger.error("Error in transcribeDocument function:", error);
      
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