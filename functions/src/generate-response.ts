import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { VertexAI, Part, Content } from "@google-cloud/vertexai";

// Initialize Firebase Admin if not already initialized
if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

// Vertex AI設定
const vertex_ai = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT || "lingosavor",
  location: "us-central1",
});

// モデル名を技術名に変換する関数
function getModelTechnicalName(modelKey: string): string {
  switch (modelKey) {
    case 'fast':
      return 'gemini-2.5-flash-lite';
    case 'smart':
      return 'gemini-2.5-flash';
    default:
      return 'gemini-2.5-flash-lite';
  }
}

// プランに応じてモデルを取得する関数
function getModelFromPlan(plan: string): string {
  switch (plan) {
    case 'premium':
      return 'advanced';
    case 'pro':
      return 'smart';
    case 'free':
    default:
      return 'fast';
  }
}

interface Message {
  role: 'user' | 'model';
  content: string;
  created_at: any;
}

export const generateResponse = onCall(
  {
    maxInstances: 5,
    timeoutSeconds: 540,
    memory: "256MiB",
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

      const { room_id } = data;

      if (!room_id) {
        throw new HttpsError(
          'invalid-argument',
          'room_id is required'
        );
      }

      logger.info(`Generating response for room: ${room_id} for user: ${auth.uid}`);

      // 1. roomsコレクションからroomを検索
      const roomRef = db.collection("user_rooms").doc(room_id);
      const roomDoc = await roomRef.get();

      if (!roomDoc.exists) {
        throw new HttpsError(
          'not-found',
          'Room not found'
        );
      }

      const roomData = roomDoc.data();
      
      // リクエストしたユーザーがルームの所有者かチェック
      if (roomData?.user_id !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'このルームにアクセスする権限がありません。'
        );
      }
      
      logger.info(`Room found: ${roomData?.title}`);
      
      // document_idを取得
      const documentId = roomData?.document_id;
      let fullTranscription = "";
      
      if (documentId) {
        logger.info(`Document ID found: ${documentId}`);
        
        // user_documentsからtranscriptionを取得
        const documentRef = db.collection("user_documents").doc(documentId);
        const documentDoc = await documentRef.get();
        
        if (documentDoc.exists) {
          const documentData = documentDoc.data();
          // ドキュメントの所有者チェック
          if (documentData?.user_id === auth.uid) {
            fullTranscription = documentData?.transcription || "";
            logger.info(`Full transcription retrieved, length: ${fullTranscription.length}`);
          } else {
            logger.warn(`Document ${documentId} access denied for user ${auth.uid}`);
          }
        } else {
          logger.warn(`Document ${documentId} not found`);
        }
      } else {
        logger.info("No document_id found in room data");
      }

      // ユーザーのプラン情報を取得
      const userRef = db.collection("users").doc(auth.uid);
      const userDoc = await userRef.get();
      
      let userPlan = 'free';
      if (userDoc.exists) {
        const userData = userDoc.data();
        userPlan = userData?.plan || 'free';
      }
      
      // プランに応じてモデルを決定
      const modelKey = getModelFromPlan(userPlan);
      const model = getModelTechnicalName(modelKey);
      logger.info(`Using model from user plan: ${userPlan} -> ${modelKey} -> ${model}`);

      // 2. messagesコレクションからメッセージ履歴を取得
      const messagesQuery = db
        .collection("messages")
        .where("user_id", "==", roomData?.user_id)
        .where("room_id", "==", room_id)
        .orderBy("created_at", "asc");

      const messagesSnapshot = await messagesQuery.get();
      const messages: Message[] = [];

      messagesSnapshot.forEach((doc) => {
        const data = doc.data();
        messages.push({
          role: data.role,
          content: data.content,
          created_at: data.created_at,
        });
      });

      logger.info(`Found ${messages.length} messages in room`);

      // 4. AI応答を生成
      const aiResponse = await generateAIResponse(messages, roomData?.user_id || null, model, fullTranscription);
      
      if (!aiResponse) {
        throw new HttpsError(
          'internal',
          'Failed to generate AI response'
        );
      }

      // 6. AI応答をmessagesコレクションに保存
      await db.collection("messages").add({
        role: "model",
        user_id: roomData?.user_id || null,
        created_at: FieldValue.serverTimestamp(),
        content: aiResponse,
        room_id: room_id,
      });

      logger.info("AI response saved successfully");

      return {
        success: true,
        message: "Response generated successfully",
        response: aiResponse,
      };

    } catch (error) {
      logger.error("Error generating response:", error);
      
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



async function generateAIResponse(
  messages: Message[], 
  userId: string | null,
  model: string,
  fullTranscription?: string
): Promise<string | null> {
  try {
    logger.info(`Generating AI response for ${messages.length} messages using model: ${model}`);

    // システムインストラクション
    let systemInstruction = `あなたは親しみやすく、知識豊富な英語学習支援AIアシスタントです。
ユーザーの質問に対して、以下の方針で回答してください：

1. **わかりやすく説明**: 複雑な概念も理解しやすく説明する
2. **具体例を提供**: 実用的な例文や使用場面を示す
3. **文脈を考慮**: ユーザーの学習レベルに合わせた説明をする
4. **親しみやすいトーン**: 敬語を使いつつも親しみやすく接する
5. **実用的なアドバイス**: 学習に役立つ追加情報も提供する

ユーザーの日本語学習を効果的にサポートしてください。`;

    // 英文全文がある場合はシステムインストラクションに追加
    if (fullTranscription && fullTranscription.trim()) {
      systemInstruction += `

    ## 参考資料（英文全文）
    以下は、このセッションで参照できる英語の文書全文です。ユーザーからの質問に答える際の参考資料として活用してください：

    ${fullTranscription}`;
      logger.info(`Added full transcription to system instruction, length: ${fullTranscription.length}`);
    }

    // メッセージをGeminiのContent形式に変換
    const history: Content[] = messages.flatMap((msg) => {
      const role = msg.role;
      const parts: Part[] = [];

      // contentが存在し、空文字列でない場合のみpartsに追加
      if (msg.content && typeof msg.content === 'string' && msg.content.trim() !== '') {
        parts.push({ text: msg.content });
      }

      // partsが空の場合は、このメッセージをスキップ
      if (parts.length === 0) {
        logger.warn(`Message with role ${role} has no valid parts, skipping.`);
        return [];
      }

      return [{ role, parts }];
    });

    logger.info(`Processed ${history.length} valid messages for chat history`);

    // 最後のユーザーメッセージを取得
    let partsForSendMessage: Part[] = [];
    let chatHistoryForGemini: Content[] = [];

    if (history.length > 0 && history[history.length - 1].role === 'user') {
      // 最後のメッセージがユーザーメッセージの場合
      const lastUserMessage = history[history.length - 1];
      if (lastUserMessage.parts && lastUserMessage.parts.length > 0) {
        partsForSendMessage = lastUserMessage.parts;
      }
      chatHistoryForGemini = history.slice(0, -1); // 最後のメッセージを除いたhistory
    } else {
      // 最後のメッセージがユーザーメッセージでない場合、最後のユーザーメッセージを探す
      const userMessagesFromHistory = history.filter(h => h.role === 'user');
      if (userMessagesFromHistory.length === 0) {
        logger.error("No user messages found to respond to");
        return "申し訳ございませんが、回答するユーザーメッセージが見つかりませんでした。";
      }
      
      const lastUserMessage = userMessagesFromHistory[userMessagesFromHistory.length - 1];
      if (lastUserMessage.parts && lastUserMessage.parts.length > 0) {
        partsForSendMessage = lastUserMessage.parts;
      }
      
      const lastUserMessageIndex = history.lastIndexOf(lastUserMessage);
      chatHistoryForGemini = history.slice(0, lastUserMessageIndex >= 0 ? lastUserMessageIndex : 0);
      logger.warn(`History did not end with a user message. Using last known user message and prior history.`);
    }

    if (partsForSendMessage.length === 0) {
      logger.error("Could not determine parts for the latest user message");
      return "申し訳ございませんが、有効なユーザーメッセージが見つかりませんでした。";
    }

    logger.info(`Chat history length: ${chatHistoryForGemini.length}, Parts for send message: ${JSON.stringify(partsForSendMessage)}`);

    // GenerativeModelを作成
          const generativeModelWithSystem = vertex_ai.getGenerativeModel({
        model: model,
      systemInstruction: systemInstruction,
      generationConfig: {
        maxOutputTokens: 4096,
        temperature: 0.7,
        topP: 0.95,
      },
    });

    // チャットを開始
    const chat = generativeModelWithSystem.startChat({
      history: chatHistoryForGemini,
    });

    // メッセージを送信
    const result = await chat.sendMessage(partsForSendMessage);
    const modelResponse = result.response;

    if (!modelResponse || !modelResponse.candidates || modelResponse.candidates.length === 0) {
      logger.error("No response from Gemini", result);
      return "申し訳ございませんが、AIからの応答を取得できませんでした。もう一度お試しください。";
    }

    let aiResponseMessage = "";
    const firstCandidate = modelResponse.candidates[0];
    if (firstCandidate.content && 
        firstCandidate.content.parts && 
        firstCandidate.content.parts.length > 0 && 
        firstCandidate.content.parts[0].text) {
      aiResponseMessage = firstCandidate.content.parts[0].text;
    } else {
      logger.warn("Gemini response did not contain a text part or format was unexpected.", firstCandidate);
      aiResponseMessage = firstCandidate.content?.parts?.map((p: any) => p.text || "").join(" ").trim() || "AIからの応答にテキストが含まれていませんでした。";
    }

    logger.info(`AI response generated successfully: "${aiResponseMessage.substring(0, 100)}..."`);
    return aiResponseMessage;

  } catch (error) {
    logger.error("Error in AI response generation:", error);
    
    // エラー時のフォールバック応答
    const fallbackResponses = [
      "申し訳ございません。一時的に回答の生成でエラーが発生しました。もう一度お試しください。",
      "システムでエラーが発生しました。しばらく待ってから再度お試しください。",
      "回答の準備中にエラーが発生しました。お手数ですが、もう一度お送りください。"
    ];
    
    return fallbackResponses[Math.floor(Math.random() * fallbackResponses.length)];
  }
}

 