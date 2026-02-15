import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {VertexAI} from "@google-cloud/vertexai";
import * as logger from "firebase-functions/logger";

// Firebase Admin初期化（必要に応じて）
if (!admin.apps.length) {
  admin.initializeApp();
}

// Vertex AI設定
const vertex_ai = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT || "lingosavor",
  location: "us-central1",
});

const generativeModel = vertex_ai.preview.getGenerativeModel({
  model: "gemini-2.5-flash"
});

// 単語分割関数（機械的分割版）
function splitIntoBasicTokens(text: string): string[] {
  let processedText = text;
  
  // アポストロフィの特別処理
  // 1. 空白の後のアポストロフィ（引用符の開始）: 分割する
  processedText = processedText.replace(/(\s)([''])/g, '$1 $2 ');
  
  // 2. アポストロフィの後に空白（引用符の終了）: 分割する
  processedText = processedText.replace(/([''])(\s)/g, ' $1 $2');
  
  // 3. 文字に挟まれたアポストロフィ（所有格・短縮形）は分割しない
  // （上記の処理で既に引用符は分離されているため、残りは所有格・短縮形）
  
  // その他の句読点を独立させるための正規表現
  const punctuationRegex = /([,.!?;:"()[\]{}"`~@#$%^&*+=|\\/<>])/g;
  
  // 句読点の前後にスペースを挿入
  processedText = processedText.replace(punctuationRegex, ' $1 ');
  
  // スペースで分割し、空文字列を除去
  return processedText
    .split(/\s+/)
    .filter(token => token.length > 0);
}

// 英文判定関数
async function isEnglishText(text: string): Promise<boolean> {
  const prompt = `以下のテキストが英文（英語）として記述されているかどうかを判定してください。

判定基準：
- 主要な言語が英語であること
- 英語の文法構造に従っていること
- 英単語が主体であること
- 他言語（日本語、中国語、韓国語、フランス語、ドイツ語など）が主体でないこと

注意：
- 少数の他言語の単語や固有名詞が含まれていても、主体が英語であれば英文と判定してください
- 文法的に完璧でなくても、英語として理解可能であれば英文と判定してください
- 単語の羅列や不完全な文でも、英語の単語が主体であれば英文と判定してください

回答は以下の形式で返してください：
- 英文の場合：true
- 英文でない場合：false

テキスト：
${text}

判定結果（trueまたはfalse）:`;

  try {
    const result = await generativeModel.generateContent(prompt);
    const response = result.response.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!response) {
      logger.warn("No response from Gemini for English text detection");
      return true; // エラー時は処理を続行
    }
    
    const cleanResponse = response.trim().toLowerCase();
    const isEnglish = cleanResponse.includes('true');
    
    logger.info(`English text detection result: ${cleanResponse} -> ${isEnglish}`);
    return isEnglish;
  } catch (error) {
    logger.warn("Error in English text detection, assuming text is English:", error);
    return true; // エラー時は処理を続行
  }
}

// 概要とポイント解説を生成する関数
async function generateSummary(text: string): Promise<string> {
  const prompt = `以下の英文書類の内容を分析し、日本語で包括的に解説してください：

1. 文章の概要とポイント
- 主要なテーマと論点
- 重要な情報のまとめ

2. 文化的背景の解説
- 文章に含まれる文化的な背景
- 歴史的・社会的コンテキスト
- 外国の習慣や価値観についての説明
- 学習者が理解を深められる補足情報

上記の観点を統合して、学習者にとって有益な解説文を作成してください。

文章：
${text}

解説文をそのまま返してください`;

  const result = await generativeModel.generateContent(prompt);
  const response = result.response.candidates?.[0]?.content?.parts?.[0]?.text;
  
  if (!response) {
    throw new Error("No response from Gemini for summary");
  }
  
  return response.trim();
}

// 段落を分割し、各段落について機械的に単語分割する関数
function analyzeParagraphsWithWords(paragraphs: string[]): Array<{paragraph: string, words: string[]}> {
  return paragraphs.map(paragraph => ({
    paragraph: paragraph,
    words: splitIntoBasicTokens(paragraph)
  }));
}

// 文章全体から文を抽出する関数
function extractSentencesFromParagraphs(paragraphs: string[]): string[] {
  const sentences: string[] = [];
  const sentenceEndRegex = /(?<=[.?!])\s+/;

  for (const paragraph of paragraphs) {
    const paragraphSentences = paragraph
      .split(sentenceEndRegex)
      .map(s => s.trim())
      .filter(s => s.length > 0);
    sentences.push(...paragraphSentences);
  }

  return sentences;
}



// 単語を正規化する関数（published_wordsと同じロジック）
function normalizeWord(word: string): string {
  return word.toLowerCase().trim();
}

// ドキュメントIDに変換する関数（published_wordsと同じロジック）
function toDocumentId(word: string): string {
  return normalizeWord(word).replace(/\//g, "_SLASH_").replace(/\./g, "_DOT_");
}

// 型定義
interface PublishedWordAppearance {
  wordlistId: string;
  wordlistTitle: string;
  number?: number;
  page?: number;
  type: "main" | "derivative" | "synonym" | "antonym";
  parentWord?: string;
}

interface PublishedWordData {
  word: string;
  appearances: PublishedWordAppearance[];
}

interface WordlistMetadata {
  id: string;
  title: string;
  total_words: number;
}

interface WordDocument {
  word: string;
  number: number;
  page?: number;
  type: "main" | "derivative" | "synonym" | "antonym";
  parentWord?: string;
}

// ユーザーの登録単語帳からマッチする単語を取得する関数
async function getMatchedPublishedWords(
  words: string[],
  userId: string
): Promise<Record<string, PublishedWordData>> {
  const db = admin.firestore();
  const result: Record<string, PublishedWordData> = {};

  // 1. ユーザーの登録単語帳IDを取得
  const userDoc = await db.collection("users").doc(userId).get();
  const userData = userDoc.data();
  const subscribedWordlists: string[] = userData?.subscribed_wordlists || [];

  if (subscribedWordlists.length === 0) {
    logger.info("User has no subscribed wordlists");
    return result;
  }

  logger.info(`User subscribed wordlists: ${subscribedWordlists.join(", ")}`);

  // 2. 各単語帳のメタデータを取得
  const wordlistMetadataMap: Record<string, WordlistMetadata> = {};
  for (const wordlistId of subscribedWordlists) {
    const wordlistDoc = await db.collection("published_wordlists").doc(wordlistId).get();
    if (wordlistDoc.exists) {
      wordlistMetadataMap[wordlistId] = wordlistDoc.data() as WordlistMetadata;
    }
  }

  // 3. 単語を正規化して重複を除去
  const uniqueWords = [...new Set(
    words
      .map(w => normalizeWord(w))
      .filter(w => w.length > 1 && /^[a-z]/.test(w)) // 英単語のみ（2文字以上、英字で始まる）
  )];

  if (uniqueWords.length === 0) {
    return result;
  }

  logger.info(`Checking ${uniqueWords.length} unique words against ${subscribedWordlists.length} wordlists`);

  // 4. 各単語帳のwordsサブコレクションから単語を検索
  const BATCH_SIZE = 100; // 単語帳ごとにバッチ処理

  for (const wordlistId of subscribedWordlists) {
    const metadata = wordlistMetadataMap[wordlistId];
    if (!metadata) continue;

    const wordsCollection = db.collection("published_wordlists").doc(wordlistId).collection("words");

    for (let i = 0; i < uniqueWords.length; i += BATCH_SIZE) {
      const batch = uniqueWords.slice(i, i + BATCH_SIZE);
      const docRefs = batch.map(word => wordsCollection.doc(toDocumentId(word)));

      try {
        const snapshots = await db.getAll(...docRefs);

        for (const snapshot of snapshots) {
          if (snapshot.exists) {
            const wordData = snapshot.data() as WordDocument;
            const normalizedWord = wordData.word;

            // 結果に追加（既存の場合はappearancesに追加）
            if (!result[normalizedWord]) {
              result[normalizedWord] = {
                word: normalizedWord,
                appearances: [],
              };
            }

            const appearance: PublishedWordAppearance = {
              wordlistId: wordlistId,
              wordlistTitle: metadata.title,
              number: wordData.number,
              type: wordData.type,
            };

            if (wordData.page !== undefined) {
              appearance.page = wordData.page;
            }

            if (wordData.parentWord) {
              appearance.parentWord = wordData.parentWord;
            }

            result[normalizedWord].appearances.push(appearance);
          }
        }
      } catch (error) {
        logger.warn(`Error fetching words from ${wordlistId}:`, error);
      }
    }
  }

  logger.info(`Found ${Object.keys(result).length} matched published words`);
  return result;
}

// 文章配列を翻訳する関数
async function translateSentences(sentences: string[]): Promise<Array<{raw: string, translation: string}>> {
  const prompt = `以下の英文を一文ずつ自然な日本語に翻訳してください。
英文：
${sentences.map((s, i) => `${i + 1}. ${s}`).join('\n')}

回答は以下のJSON形式で返してください：
[
  {"raw": "元の英文1", "translation": "翻訳した日本語1"},
  {"raw": "元の英文2", "translation": "翻訳した日本語2"},
  ...
]
  
文頭に番号をつけることを禁止します。
  `;

  try {
    const result = await generativeModel.generateContent(prompt);
    const response = result.response.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!response) {
      throw new Error("No response from Gemini for translation");
    }
    
    const jsonMatch = response.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    } else {
      throw new Error("No valid JSON found in translation response");
    }
  } catch (error) {
    logger.warn("Error in translation, using fallback:", error);
    // フォールバック
    return sentences.map(sentence => ({
      raw: sentence,
      translation: "翻訳を生成できませんでした。"
    }));
  }
}

export const savorDocument = onCall(
  {
    timeoutSeconds: 540, // 9分のタイムアウト
    memory: "1GiB",     // 最大メモリ
  },
  async (request) => {
    let documentId: string | undefined;
    let requiredGems: number = 0;
    let userDocRef: admin.firestore.DocumentReference | undefined;
    let gemsConsumed: boolean = false;
    try {
      const { data, auth } = request;
      
      // 認証済みユーザーかどうかを確認
      if (!auth) {
        throw new HttpsError(
          'unauthenticated',
          'この機能を利用するには認証が必要です。'
        );
      }

      const {documentId: docId}: {documentId: string} = data;
      documentId = docId;

      if (!documentId) {
        throw new HttpsError(
          'invalid-argument',
          'Document ID is required'
        );
      }

      logger.info(`Starting savor analysis for document: ${documentId} for user: ${auth.uid}`);

      // Firestoreからドキュメント情報を取得
      const docRef = admin.firestore().collection("user_documents").doc(documentId);
      
      // statusを「処理中」に更新
      await docRef.update({
        status: '処理中'
      });
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

      const user_id = docData.user_id;
      const transcription = docData.transcription;

      // リクエストしたユーザーがドキュメントの所有者かチェック
      if (user_id !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'このドキュメントにアクセスする権限がありません。'
        );
      }

      if (!transcription || transcription.trim().length === 0) {
        throw new HttpsError(
          'failed-precondition',
          'Transcription not found. Please transcribe the document first.'
        );
      }

      // 文字起こし済みテキストが英文かどうかをチェック
      const isEnglish = await isEnglishText(transcription);
      if (!isEnglish) {
        throw new HttpsError(
          'failed-precondition',
          'Transcription is not English. Please transcribe English text.'
        );
      }

      logger.info(`Retrieved document info: user_id=${user_id}, transcription_length=${transcription.length}`);

      // transcriptionの単語数をカウントしてgem必要量を計算
      const wordCount = transcription.trim().split(/\s+/).length;
      requiredGems = Math.ceil(wordCount / 10);
      
      logger.info(`Word count: ${wordCount}, Required gems: ${requiredGems}`);

      // ユーザーのgem残高をチェック
      userDocRef = admin.firestore().collection("users").doc(user_id);
      const userDocSnapshot = await userDocRef.get();

      if (!userDocSnapshot.exists) {
        throw new HttpsError(
          'not-found',
          'User data not found'
        );
      }

      const userData = userDocSnapshot.data();
      if (!userData) {
        throw new HttpsError(
          'not-found',
          'User data not found'
        );
      }

      const userPlan = userData.plan || 'free';
      const currentGems = userData.gems || 0;

      // standard または pro プランの場合は gem を消費しない
      const isPremiumPlan = userPlan === 'standard' || userPlan === 'pro';

      if (!isPremiumPlan) {
        // free プランの場合は gem をチェック
        if (currentGems < requiredGems) {
          throw new HttpsError(
            'resource-exhausted',
            `Insufficient gems: required ${requiredGems}, current ${currentGems}`
          );
        }

        logger.info(`Gem check passed: ${currentGems} >= ${requiredGems}`);

        // gemを消費（処理開始時点で即座に減らす）
        await userDocRef.update({
          gems: admin.firestore.FieldValue.increment(-requiredGems)
        });
        gemsConsumed = true;
        logger.info(`Gems consumed: ${requiredGems} gems deducted from user ${user_id}`);
      } else {
        logger.info(`Premium plan detected (${userPlan}): skipping gem consumption`);
        requiredGems = 0; // プレミアムプランの場合は消費 gem を 0 に設定
      }

      // 文字起こし済みテキストを使用して機械的に段落分割
      const extractedText = transcription;
      const paragraphs = extractedText.split('\n').filter((p: string) => p.trim() !== '');

      // 並列処理の開始
      logger.info("Starting parallel processing...");

      // 2. 段落を分割し、各段落を機械的に単語分割
      const paragraphsWithWords = analyzeParagraphsWithWords(paragraphs);

      // 全単語を抽出
      const allWords = paragraphsWithWords.flatMap(p => p.words);

      // 並列処理: summary生成、翻訳、published_wordlistsマッチング
      const sentences = extractSentencesFromParagraphs(paragraphs);
      const [summary, sentenceTranslations, matchedPublishedWords] = await Promise.all([
        generateSummary(extractedText),
        translateSentences(sentences),
        getMatchedPublishedWords(allWords, user_id),
      ]);

      logger.info("Parallel processing completed");

      // 結果をまとめる
      const savorResult = {
        summary: summary,
        paragraphs: paragraphs,
        paragraphs_with_words: paragraphsWithWords,
        sentence_translations: sentenceTranslations,
        matched_published_words: matchedPublishedWords,
        user_id: user_id,
      };

      // Firestoreに結果を保存（documents_savor_resultsコレクションに）
      await admin.firestore().collection("documents_savor_results").doc(documentId).set(savorResult);

      // audioタイプの場合、追加の音声処理を実行
      if (docData.type === "audio" && docData.path) {
        try {
          logger.info("Starting audio processing for overlapping audio generation");
          
          // text-to-speech.tsからcreateAudioOverlapsInternalを呼び出し
          const {createAudioOverlapsInternal} = await import('./text-to-speech.js');
          
          await createAudioOverlapsInternal({
            audioStorageUri: docData.path,
            userId: user_id,
            documentId: documentId,
          });
          
          logger.info("Audio processing completed successfully");
          
        } catch (audioError) {
          logger.error("Error in audio processing:", audioError);
          // 音声処理エラーは処理を停止させずに警告のみ
        }
      }

      // Firebase Storageからファイルを削除
      try {
        const bucket = admin.storage().bucket("lingosavor.firebasestorage.app");
        const documentType = docData.type;
        const documentPath = docData.path;
        const imagePaths = docData.image_paths;

        if (documentType === "audio") {
          // audioファイルは削除しない
          logger.info(`Skipping file deletion for audio type document: ${documentId}`);
        } else if (documentType === "image" && Array.isArray(imagePaths)) {
          // 複数の画像ファイルを削除
          let allDeletedSuccessfully = true;
          const deletePromises = imagePaths.map(async (gsPath: string) => {
            try {
              // gs://lingosavor.firebasestorage.app/ の部分を除去してファイルパスを取得
              const filePath = gsPath.replace("gs://lingosavor.firebasestorage.app/", "");
              await bucket.file(filePath).delete();
              logger.info(`Successfully deleted image file: ${filePath}`);
            } catch (deleteError) {
              logger.warn(`Failed to delete image file: ${gsPath}`, deleteError);
              allDeletedSuccessfully = false;
            }
          });
          await Promise.all(deletePromises);
          
          // 全ての画像削除が成功した場合、image_pathsフィールドを削除
          if (allDeletedSuccessfully) {
            await docRef.update({
              image_paths: admin.firestore.FieldValue.delete()
            });
            logger.info(`Successfully removed image_paths field from document: ${documentId}`);
          }
        } else if (documentType === "file" && typeof documentPath === "string") {
          // 単一のファイルを削除
          try {
            const filePath = documentPath.replace("gs://lingosavor.firebasestorage.app/", "");
            await bucket.file(filePath).delete();
            logger.info(`Successfully deleted file: ${filePath}`);
            
            // ファイル削除が成功した場合、pathフィールドを削除
            await docRef.update({
              path: admin.firestore.FieldValue.delete()
            });
            logger.info(`Successfully removed path field from document: ${documentId}`);
          } catch (deleteError) {
            logger.warn(`Failed to delete file: ${documentPath}`, deleteError);
          }
        } else if (documentType === "text") {
          // textタイプはファイルアップロードではないため、削除処理は不要
          logger.info(`Skipping file deletion for text type document: ${documentId}`);
        } else {
          logger.warn(`Unexpected document type or path format: type=${documentType}, path=${documentPath}`);
        }
      } catch (storageError) {
        logger.warn("Error deleting files from storage (processing will continue):", storageError);
      }

      // statusを「解析済み」に更新
      await docRef.update({
        status: '解析済み'
      });

      logger.info(`Savor analysis completed for document: ${documentId}, consumed ${requiredGems} gems`);

      return {
        success: true,
        documentId: documentId,
        consumed_gems: requiredGems
      };

    } catch (error) {
      logger.error("Error in savorDocument function:", error);

      // エラー時はgemを返却（既に消費されている場合）
      if (gemsConsumed && userDocRef && requiredGems > 0) {
        try {
          await userDocRef.update({
            gems: admin.firestore.FieldValue.increment(requiredGems)
          });
          logger.info(`Gems refunded: ${requiredGems} gems returned to user due to error`);
        } catch (refundError) {
          logger.error("Failed to refund gems on error:", refundError);
        }
      }

      // エラー時はstatusを「未解析」に戻す
      try {
        if (documentId) {
          const docRef = admin.firestore().collection("user_documents").doc(documentId);
          await docRef.update({
            status: '未解析'
          });
        }
      } catch (statusUpdateError) {
        logger.error("Failed to update status to '未解析' on error:", statusUpdateError);
      }

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