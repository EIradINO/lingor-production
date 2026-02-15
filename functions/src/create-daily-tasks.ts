import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { VertexAI } from '@google-cloud/vertexai';
import { TextToSpeechClient } from '@google-cloud/text-to-speech';

// Firebase Admin初期化（既に初期化されている場合はスキップ）
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();
const storage = getStorage();

// Vertex AI初期化
const vertexAI = new VertexAI({ 
  project: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT, 
  location: 'us-central1' 
});

// Text-to-Speech初期化
const ttsClient = new TextToSpeechClient();

// WordListItem型定義
interface WordListItem {
  word: string;
  meaning: string[];
  id: string;
}

// TargetUser型定義
interface TargetUser {
  user_id: string;
  lastReviewed: Date;
  plan: string;
  type: 'completed' | 'uncreated';
  isCompleted?: string[]; // completedタイプの場合のみ
}

// Review interface
interface Review {
  isCorrect: boolean;
  timestamp: Date;
}

// Simplified retention calculation function based on review frequency
function calculateEbbinghausRetention(
  currentDate: Date,
  createdAt: Date,
  reviewHistory: Review[]
): boolean {
  // 復習データを時系列（timestampの昇順）でソート
  const sortedReviews = [...reviewHistory].sort(
    (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
  );

  // 最後の復習日時を取得（復習履歴がない場合は作成日を使用）
  let lastReviewTimestamp = createdAt;
  if (sortedReviews.length > 0) {
    lastReviewTimestamp = sortedReviews[sortedReviews.length - 1].timestamp;
  }

  // 最後の復習から現在までの経過日数を四捨五入で計算
  const daysSinceLastReview = Math.round(
    (currentDate.getTime() - lastReviewTimestamp.getTime()) / (1000 * 60 * 60 * 24)
  );

  // 復習データを日毎にグループ分け
  const reviewsByDay = new Map<string, Review[]>();
  
  for (const review of sortedReviews) {
    // 日付文字列をキーとして使用（YYYY-MM-DD形式）
    const dateKey = review.timestamp.toISOString().split('T')[0];
    
    if (!reviewsByDay.has(dateKey)) {
      reviewsByDay.set(dateKey, []);
    }
    reviewsByDay.get(dateKey)!.push(review);
  }

  // 復習した日数（グループ数）を取得
  const reviewDayCount = reviewsByDay.size;

  // グループ数に応じた復習判定
  let shouldReview = false;
  
  if (reviewDayCount === 0) {
    // 0個: daysSinceLastReviewが1日以上なら復習すべき
    shouldReview = daysSinceLastReview >= 1;
  } else if (reviewDayCount === 1) {
    // 1個: daysSinceLastReviewが3日以上なら復習すべき
    shouldReview = daysSinceLastReview >= 3;
  } else {
    // 2個以上: daysSinceLastReviewが7日以上なら復習すべき
    shouldReview = daysSinceLastReview >= 7;
  }

  // 復習すべき場合はtrue、そうでなければfalseを返す
  return shouldReview;
}

// TTSで音声を生成してStorageに保存する関数
async function generateAndSaveAudio(text: string, userId: string, suffix: string = ''): Promise<string> {
  try {
    const request = {
      input: { text },
      voice: { languageCode: 'en-US', ssmlGender: 'NEUTRAL' as const },
      audioConfig: { audioEncoding: 'MP3' as const },
    };

    const [response] = await ttsClient.synthesizeSpeech(request);
    
    if (!response.audioContent) {
      throw new Error('音声コンテンツが生成されませんでした');
    }

    // Firebase Storageに保存
    const baseFileName = `daily-listening-${new Date().toISOString().split('T')[0]}`;
    const fileName = suffix ? `${baseFileName}-${suffix}.mp3` : `${baseFileName}.mp3`;
    const filePath = `documents/${userId}/${fileName}`;
    const file = storage.bucket().file(filePath);
    
    await file.save(response.audioContent as Buffer, {
      metadata: {
        contentType: 'audio/mp3',
      },
    });
    
    // 公開URLを取得
    await file.makePublic();
    const publicUrl = `https://storage.googleapis.com/${storage.bucket().name}/${filePath}`;
    
    return publicUrl;
  } catch (error) {
    logger.error('音声生成に失敗しました', { error, userId, suffix });
    throw error;
  }
}


// Grammar List作成の関数
async function createGrammarList(userId: string, lastReviewed: Date, plan: string): Promise<any[]> {
  logger.info(`Creating grammar list for user: ${userId}, plan: ${plan}`);
  
  const grammarQuizzes: any[] = [];
  
  try {
    // 1. messagesをuser_idでフィルタリングし、lastReviewed以降に作られたmessagesを取得
    logger.info(`Querying messages for user: ${userId}`, {
      userId,
      lastReviewed: lastReviewed.toISOString(),
      plan
    });
    
    const messagesSnapshot = await db
      .collection('messages')
      .where('user_id', '==', userId)
      .where('created_at', '>', lastReviewed)
      .get();
    
    if (messagesSnapshot.empty) {
      logger.info(`No new messages found for user: ${userId} since ${lastReviewed.toISOString()}`);
      return grammarQuizzes;
    }
    
    logger.info(`Found ${messagesSnapshot.size} new messages for user: ${userId}`);
    
    // 2. room_idごとにグループ分け
    const messagesByRoom = new Map<string, any[]>();
    messagesSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const roomId = data.room_id;
      if (roomId) {
        if (!messagesByRoom.has(roomId)) {
          messagesByRoom.set(roomId, []);
        }
        messagesByRoom.get(roomId)!.push(data);
      }
    });
    
    logger.info(`Found messages in ${messagesByRoom.size} rooms`);
    
    // 3. roomごとのデータを準備
    const roomProcessingData: Array<{
      roomId: string;
      newMessages: any[];
      userRoomDoc: any;
      userRoomData: any;
      documentId: string;
      script: string;
      allMessages: any[];
    }> = [];

    for (const [roomId, newMessages] of messagesByRoom) {
      try {
        // user_roomsを取得
        const userRoomDoc = await db.collection('user_rooms').doc(roomId).get();
        if (!userRoomDoc.exists) {
          logger.warn(`User room not found: ${roomId}`);
          continue;
        }
        
        const userRoomData = userRoomDoc.data()!;
        const documentId = userRoomData.document_id;
        
        if (!documentId) {
          logger.warn(`No document_id found for room: ${roomId}`);
          continue;
        }
        
        // user_documentsからtranscriptionを取得
        const userDocumentDoc = await db.collection('user_documents').doc(documentId).get();
        if (!userDocumentDoc.exists) {
          logger.warn(`User document not found: ${documentId}`);
          continue;
        }
        
        const userDocumentData = userDocumentDoc.data()!;
        const script = userDocumentData.transcription || '';
        
        if (!script) {
          logger.warn(`No transcription found for document: ${documentId}`);
          continue;
        }
        
        // 該当room_idの全メッセージを取得
        const allMessagesSnapshot = await db
          .collection('messages')
          .where('room_id', '==', roomId)
          .orderBy('created_at', 'asc')
          .get();
        
        const allMessages = allMessagesSnapshot.docs.map(doc => doc.data());
        
        roomProcessingData.push({
          roomId,
          newMessages,
          userRoomDoc,
          userRoomData,
          documentId,
          script,
          allMessages
        });
        
      } catch (error) {
        logger.error(`Error preparing room data: ${roomId}`, { 
          error: error instanceof Error ? error.message : String(error),
          roomId,
          userId
        });
      }
    }

    // 4. 50個ずつのバッチでGemini APIを並列処理
    const BATCH_SIZE = 50;
    for (let i = 0; i < roomProcessingData.length; i += BATCH_SIZE) {
      const batch = roomProcessingData.slice(i, i + BATCH_SIZE);
      logger.info(`Processing Gemini API batch ${Math.floor(i / BATCH_SIZE) + 1}, rooms ${i + 1}-${Math.min(i + BATCH_SIZE, roomProcessingData.length)} of ${roomProcessingData.length}`);
      
      // バッチ内の各roomを並列処理
      const batchPromises = batch.map(async (roomData) => {
        const { roomId, newMessages, userRoomDoc, script, allMessages } = roomData;
        
        try {
          // プランに応じたGeminiモデルを選択
          let modelName = 'gemini-2.5-flash-lite';
          if (plan === 'pro') {
            modelName = 'gemini-2.5-flash';
          } 
          
          const planModel = vertexAI.preview.getGenerativeModel({
            model: modelName,
            generationConfig: {
              responseMimeType: 'application/json',
            },
          });
          
          // Geminiへのプロンプト作成
          const messagesText = allMessages.map(msg => 
            `${msg.sender || 'User'}: ${msg.content || ''}`
          ).join('\n');
          
          const newMessagesText = newMessages.map(msg => 
            `${msg.sender || 'User'}: ${msg.content || ''}`
          ).join('\n');
          
          const prompt = `以下の英文と会話内容を参考に、文法事項の復習用の四択問題を数問作成してください。

【重要】問題は、roomの内容や会話の文脈を参照しなくても、問題文単体で完全に理解できるように作成してください。問題文には必要な情報をすべて含め、選択肢も明確に区別できるようにしてください。

本文: ${script}
会話: 全体の内容: ${messagesText}
未復習の内容: ${newMessagesText}

出力形式: 
{"abstract": "文法事項の概要を日本語で記述してください", "quizzes": [{"question": "問題文（文脈に依存しない完全な問題文）", "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"], "answer": 0}]}`;
          
          // Geminiに送信
          logger.info(`Sending prompt to Gemini for room: ${roomId}`, {
            roomId,
            userId,
            modelName,
            promptLength: prompt.length
          });
          
          const result = await planModel.generateContent(prompt);
          const response = result.response;
          const text = response.candidates?.[0]?.content?.parts?.[0]?.text;
          
          if (!text) {
            logger.error(`Empty response from Gemini for room: ${roomId}`, {
              roomId,
              userId,
              response: JSON.stringify(response, null, 2)
            });
            return null;
          }
          
          // JSONを解析
          const jsonMatch = text.match(/\{[\s\S]*\}/);
          if (!jsonMatch) {
            logger.error(`No JSON found in Gemini response for room: ${roomId}`, {
              roomId,
              userId,
              responseText: text
            });
            return null;
          }
          
          let grammarResult;
          try {
            grammarResult = JSON.parse(jsonMatch[0]);
          } catch (parseError) {
            logger.error(`Failed to parse JSON for room: ${roomId}`, {
              roomId,
              userId,
              jsonText: jsonMatch[0],
              parseError: parseError instanceof Error ? parseError.message : String(parseError)
            });
            return null;
          }
          
          const abstract = grammarResult.abstract || '';
          const quizzes = grammarResult.quizzes || [];
          
          // quizzesを収集（各クイズにroom_idを付与）
          const quizzesWithRoomId = quizzes && Array.isArray(quizzes) 
            ? quizzes.map((quiz: any) => ({
                ...quiz,
                room_id: roomId,
              }))
            : [];
          
          // user_roomsのabstractフィールドを更新し、stageをunreviewedに、reviewDataを削除
          await userRoomDoc.ref.update({
            abstract: abstract,
            stage: 'unreviewed',
            reviewData: null
          });
          
          logger.info(`Updated grammar abstract for room: ${roomId}`, {
            abstractLength: abstract.length,
            quizzesCount: quizzes.length
          });
          
          return {
            roomId,
            quizzes: quizzesWithRoomId
          };
          
        } catch (error) {
          logger.error(`Error processing room: ${roomId}`, { 
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
            roomId,
            userId
          });
          return null;
        }
      });
      
      // バッチの結果を待機
      const batchResults = await Promise.all(batchPromises);
      
      // 結果をgrammarQuizzesに追加
      batchResults.forEach(result => {
        if (result && result.quizzes) {
          grammarQuizzes.push(...result.quizzes);
        }
      });
      
      // バッチ間で少し待機（レート制限対策）
      if (i + BATCH_SIZE < roomProcessingData.length) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
    
    return grammarQuizzes;
    
  } catch (error) {
    logger.error(`Error creating grammar list for user: ${userId}`, { 
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
      userId,
      lastReviewed: lastReviewed.toISOString(),
      plan
    });
    throw error; // エラーを再スローして上位で処理されるようにする
  }
}

// Reading/Listening問題作成の関数
async function createReadingListeningTask(
  userId: string, 
  plan: string, 
  taskType: 'reading' | 'listening',
  previousTaskContent?: string,
  userImpression?: string
): Promise<any> {
  logger.info(`Creating ${taskType} task for user: ${userId}, plan: ${plan}`);
  
  try {
    // user_wordsのstageがtaskTypeに応じたものを優先順位で取得
    const targetStage = taskType === 'reading' ? 'reading' : 'listening';
    const userWordsSnapshot = await db
      .collection('user_words')
      .where('user_id', '==', userId)
      .where('stage', '==', targetStage)
      .get();
    
    // reviewDataのtaskTypeに応じた数で分類
    const wordsByReviewCount = new Map<number, any[]>();
    userWordsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const reviewData = data.reviewData;
      const reviewCount = taskType === 'reading' 
        ? (reviewData?.reading ? reviewData.reading.length : 0)
        : (reviewData?.listening ? reviewData.listening.length : 0);
      
      if (!wordsByReviewCount.has(reviewCount)) {
        wordsByReviewCount.set(reviewCount, []);
      }
      wordsByReviewCount.get(reviewCount)!.push(doc);
    });
    
    // 優先順位で単語を取得（0個→1個→2個の順）
    const selectedWords: string[] = [];
    for (let reviewCount = 0; reviewCount <= 2 && selectedWords.length < 5; reviewCount++) {
      const wordsWithCount = wordsByReviewCount.get(reviewCount) || [];
      // ランダムに並べ替え
      const shuffledWords = wordsWithCount.sort(() => Math.random() - 0.5);
      
      for (const wordDoc of shuffledWords) {
        if (selectedWords.length >= 5) break;
        
        const wordData = wordDoc.data();
        const dictionaryWordId = wordData.word_id;
        
        if (dictionaryWordId) {
          try {
            const dictionaryDoc = await db.collection('dictionary').doc(dictionaryWordId).get();
              if (dictionaryDoc.exists) {
                const dictionaryData = dictionaryDoc.data();
              selectedWords.push(dictionaryData?.word || '');
            }
          } catch (error) {
            logger.warn(`Failed to fetch dictionary data for word_id: ${dictionaryWordId}`, { error });
          }
        }
      }
    }
    
    // user_roomsのstageがtaskTypeに応じたものを優先順位で取得
    const userRoomsSnapshot = await db
      .collection('user_rooms')
      .where('user_id', '==', userId)
      .where('stage', '==', targetStage)
      .get();
    
    // reviewDataのtaskTypeに応じた数で分類
    const roomsByReviewCount = new Map<number, any[]>();
    userRoomsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const reviewData = data.reviewData;
      const reviewCount = taskType === 'reading' 
        ? (reviewData?.reading ? reviewData.reading.length : 0)
        : (reviewData?.listening ? reviewData.listening.length : 0);
      
      if (!roomsByReviewCount.has(reviewCount)) {
        roomsByReviewCount.set(reviewCount, []);
      }
      roomsByReviewCount.get(reviewCount)!.push(doc);
    });
    
    // 優先順位でルームを取得（0個→1個→2個の順）
    const selectedAbstracts: string[] = [];
    for (let reviewCount = 0; reviewCount <= 2 && selectedAbstracts.length < 5; reviewCount++) {
      const roomsWithCount = roomsByReviewCount.get(reviewCount) || [];
      // ランダムに並べ替え
      const shuffledRooms = roomsWithCount.sort(() => Math.random() - 0.5);
      
      for (const roomDoc of shuffledRooms) {
        if (selectedAbstracts.length >= 5) break;
        
        const roomData = roomDoc.data();
        const abstract = roomData.abstract;
        
        if (abstract) {
          selectedAbstracts.push(abstract);
        }
      }
    }
    
    logger.info(`Selected content for ${taskType} task`, {
      userId,
      wordsCount: selectedWords.length,
      abstractsCount: selectedAbstracts.length
    });
    
    // selectedWordsとselectedAbstractsが両方とも空の場合はタスクを生成しない
    if (selectedWords.length === 0 && selectedAbstracts.length === 0) {
      logger.info(`No content available for ${taskType} task, skipping generation`, {
        userId,
        taskType,
        wordsCount: selectedWords.length,
        abstractsCount: selectedAbstracts.length
      });
      return null;
    }
    
    // プランに応じたGeminiモデルを選択
    let modelName = 'gemini-2.5-flash-lite';
    if (plan === 'pro') {
      modelName = 'gemini-2.5-flash';
    } 
    
    const planModel = vertexAI.preview.getGenerativeModel({
      model: modelName,
      generationConfig: {
        responseMimeType: 'application/json',
      },
    });
    
    // プロンプト作成
    let prompt = `以下の${selectedWords.length}個の単語・および文法事項を用いた200語程度の英文と、その英文に関する四択問題を2問作成してください。全て英語で作成してください。`;
    
    // 前回のタスクがあれば難易度調整情報を追加
    if (previousTaskContent && userImpression) {
      prompt += `\n難易度について、以下の英文に対しユーザーは以下の感想を抱いたそうです。
英文: ${previousTaskContent}
感想: ${userImpression}`;
    }
    
    prompt += `\n\n単語: [${selectedWords.map(word => `"${word}"`).join(',')}]
文法事項: [${selectedAbstracts.map(abstract => `"${abstract}"`).join(',')}]

出力は以下のJSON形式で厳密に行ってください：
{
  "text": "200語程度の英文",
  "questions": [
    {
      "question": "問題文1",
      "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"],
      "answer": 0
    },
    {
      "question": "問題文2", 
      "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"],
      "answer": 1
    }
  ]
}

JSONのみを出力し、他の説明は不要です。`;
    
    // Geminiに送信
    const result = await planModel.generateContent(prompt);
    const response = result.response;
    const text = response.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!text) {
      throw new Error(`Empty response from Gemini for ${taskType} task`);
    }
    
    // JSONを解析
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error(`No JSON found in Gemini response for ${taskType} task`);
    }
    
    const taskContent = JSON.parse(jsonMatch[0]);
    
    logger.info(`Generated ${taskType} task for user: ${userId}`, {
      textLength: taskContent.text ? taskContent.text.length : 0,
      questionsCount: taskContent.questions ? taskContent.questions.length : 0
    });
    
    return taskContent;
    
  } catch (error) {
    logger.error(`Error creating ${taskType} task for user: ${userId}`, { error });
    throw error;
  }
}

// user_tasksを保存する関数
async function saveUserTasks(
  userId: string,
  wordList: WordListItem[],
  grammarList: any[],
  readingTask?: any,
  listeningTask?: any,
  audioUrl?: string,
  existingTaskData?: any,
  needsWordList?: boolean,
  needsGrammarList?: boolean,
  needsReadingTask?: boolean,
  needsListeningTask?: boolean
): Promise<void> {
  try {
    const taskDate = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    
    // 既存データがある場合は一部置き換え、ない場合は新規作成
    let dailyTask: any;
    let answers: { [key: string]: number[] } = {};

    if (existingTaskData) {
      // 既存データをベースにする
      dailyTask = { ...existingTaskData };
      answers = existingTaskData.answers ? { ...existingTaskData.answers } : {};
      
      // 必要なタスクタイプのみ置き換え
      if (needsWordList) {
        dailyTask.word_list = wordList;
      }
      
      if (needsGrammarList) {
        dailyTask.grammar_list = grammarList;
        answers.grammar = grammarList.map(() => -1);
      }
      
      if (needsReadingTask && readingTask) {
        dailyTask.reading = {
          text: readingTask.text,
          questions: readingTask.questions,
          user_impression: null
        };
        answers.reading = readingTask.questions.map(() => -1);
      }
      
      if (needsListeningTask && listeningTask) {
        dailyTask.listening = {
          text: listeningTask.text,
          questions: listeningTask.questions,
          audioUrl: audioUrl || null,
          user_impression: null
        };
        answers.listening = listeningTask.questions.map(() => -1);
      }
      
      // answersとisCompletedをリセット
      dailyTask.answers = answers;
      dailyTask.isCompleted = [];
      dailyTask.createdAt = new Date(); // 更新日時を新しくする
      
    } else {
      // 新規作成
      answers = {
        grammar: grammarList.map(() => -1), // grammar問題数分の-1配列
      };

      dailyTask = {
        userId,
        date: taskDate,
        createdAt: new Date(),
        word_list: wordList,
        grammar_list: grammarList,
        isCompleted: [],
        answers: answers,
      };

      // リーディングタスクがあれば追加
      if (readingTask) {
        dailyTask.reading = {
          text: readingTask.text,
          questions: readingTask.questions,
          user_impression: null
        };
        answers.reading = readingTask.questions.map(() => -1);
      }

      // リスニングタスクがあれば追加
      if (listeningTask) {
        dailyTask.listening = {
          text: listeningTask.text,
          questions: listeningTask.questions,
          audioUrl: audioUrl || null,
          user_impression: null
        };
        answers.listening = listeningTask.questions.map(() => -1);
      }
    }

    await db.collection('user_tasks').add(dailyTask);
    
    logger.info('User tasks saved successfully', { 
      userId, 
      taskDate, 
      grammarListCount: grammarList.length,
      hasReading: !!readingTask,
      hasListening: !!listeningTask,
      hasAudioUrl: !!audioUrl,
      isUpdate: !!existingTaskData
    });
    
  } catch (error) {
    logger.error('Failed to save user tasks', { error, userId });
    throw error;
  }
}

/**
 * Scheduled function: Daily task execution at 4 AM
 * Creates review tasks for users without tasks or with completed tasks
 */
export const createDailyTasks = onSchedule({
  schedule: '0 4 * * *', // 毎日午前4時に実行
  timeZone: 'Asia/Tokyo', // 日本時間
  memory: '512MiB',
  timeoutSeconds: 1800, // 30分のタイムアウト（最大値）
}, async (event) => {
  const currentDate = new Date();
  logger.info('Daily tasks started', { timestamp: currentDate.toISOString() });

  try {
    // user_tasksとusersコレクションを取得
    const [usersSnapshot, userTasksSnapshot] = await Promise.all([
      db.collection('users').get(),
      db.collection('user_tasks').get()
    ]);
    
    if (usersSnapshot.empty) {
      logger.info('No users found in the database');
      return;
    }

    // 対象ユーザーを選択する配列
    const targetUsers: TargetUser[] = [];

    // user_tasksに存在するuser_idの集合を作成
    const userTasksUserIds = new Set<string>();
    const usersWithCompletedTasks = new Map<string, { createdAt: Date, isCompleted: string[] }>(); // isCompletedに要素があるユーザーとその情報

    userTasksSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const userId = data.userId;
      const createdAt = data.createdAt?.toDate();
      const isCompleted = data.isCompleted || [];
      
      if (userId) {
        userTasksUserIds.add(userId);
        
        // isCompletedに要素がある場合は記録
        if (Array.isArray(isCompleted) && isCompleted.length > 0 && createdAt) {
          usersWithCompletedTasks.set(userId, { createdAt, isCompleted });
        }
      }
    });

    // 1. usersにあってuser_tasksにないユーザーを追加
    usersSnapshot.docs.forEach(userDoc => {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const createdAt = userData.created_at?.toDate();
      const plan = userData.plan || '';
      
      if (!userTasksUserIds.has(userId) && createdAt) {
        targetUsers.push({
          user_id: userId,
          lastReviewed: createdAt,
          plan: plan,
          type: 'uncreated'
        });
      }
    });

    // 2. user_tasksのisCompletedに要素があるユーザーを追加
    usersWithCompletedTasks.forEach(({ createdAt, isCompleted }, userId) => {
      // usersコレクションからplanを取得
      const userDoc = usersSnapshot.docs.find(doc => doc.id === userId);
      const plan = userDoc?.data()?.plan || '';
      
      targetUsers.push({
        user_id: userId,
        lastReviewed: createdAt,
        plan: plan,
        type: 'completed',
        isCompleted: isCompleted
      });
    });

    logger.info(`Target users selected for task generation`, {
      totalUsers: usersSnapshot.size,
      targetUsersCount: targetUsers.length,
      newUsers: targetUsers.filter(u => u.type === 'uncreated').length,
      completedUsers: targetUsers.filter(u => u.type === 'completed').length
    });

    // 対象ユーザーがいない場合は処理を終了
    if (targetUsers.length === 0) {
      logger.info('No target users found for task generation');
      return;
    }

    // 10人ずつのバッチ処理
    const BATCH_SIZE = 10;
    let totalUsersProcessed = 0;

    for (let i = 0; i < targetUsers.length; i += BATCH_SIZE) {
      const batch = targetUsers.slice(i, i + BATCH_SIZE);
      logger.info(`Processing batch ${Math.floor(i / BATCH_SIZE) + 1}, users ${i + 1}-${Math.min(i + BATCH_SIZE, targetUsers.length)} of ${targetUsers.length}`);

      // バッチ内の各ユーザーを処理
      for (const targetUser of batch) {
        const { user_id: userId, lastReviewed, plan, type, isCompleted } = targetUser;
        try {
          // user_wordsをuser_idでフィルタリング
          const userWordsSnapshot = await db
            .collection('user_words')
            .where('user_id', '==', userId)
            .get();

          if (!userWordsSnapshot.empty) {
            logger.info(`Processing ${userWordsSnapshot.size} words for user: ${userId}`);

            // === user_words Stage管理ロジック ===
            
            // 1. stageがunreviewedでisCorrectDataが空でないものをreadingに変更
            const unreviewedWords = userWordsSnapshot.docs.filter(doc => {
              const stage = doc.data().stage;
              const isCorrectData = doc.data().isCorrectData;
              return stage === 'unreviewed' && 
                     isCorrectData && Array.isArray(isCorrectData) && isCorrectData.length > 0;
            });

            for (const wordDoc of unreviewedWords) {
              try {
                await wordDoc.ref.update({ stage: 'reading' });
                logger.info(`Updated stage from unreviewed to reading for word: ${wordDoc.id}`);
              } catch (error) {
                logger.error(`Failed to update stage to reading for word: ${wordDoc.id}`, { error });
              }
            }

            // 2. stageがreadingでreviewDataのreadingが3個以上のものをlisteningに変更
            const readingStageWords = userWordsSnapshot.docs.filter(doc => doc.data().stage === 'reading');
            
            for (const wordDoc of readingStageWords) {
              const wordData = wordDoc.data();
              const reviewData = wordData.reviewData;
              
              if (reviewData && reviewData.reading && Array.isArray(reviewData.reading) && reviewData.reading.length >= 3) {
                try {
                  await wordDoc.ref.update({ stage: 'listening' });
                  logger.info(`Updated stage from reading to listening for word: ${wordDoc.id}`);
                } catch (error) {
                  logger.error(`Failed to update stage to listening for word: ${wordDoc.id}`, { error });
                }
              }
            }

            // 3. stageがlisteningでreviewDataのlisteningが3個以上のものをcompletedに変更
            const listeningStageWords = userWordsSnapshot.docs.filter(doc => doc.data().stage === 'listening');
            
            for (const wordDoc of listeningStageWords) {
              const wordData = wordDoc.data();
              const reviewData = wordData.reviewData;
              
              if (reviewData && reviewData.listening && Array.isArray(reviewData.listening) && reviewData.listening.length >= 3) {
                try {
                  await wordDoc.ref.update({ stage: 'completed' });
                  logger.info(`Updated stage from listening to completed for word: ${wordDoc.id}`);
                } catch (error) {
                  logger.error(`Failed to update stage to completed for word: ${wordDoc.id}`, { error });
                }
              }
            }
          }
          const userRoomsSnapshot = await db
            .collection('user_rooms')
              .where('user_id', '==', userId)
              .get();

          if (!userRoomsSnapshot.empty) {
            logger.info(`Processing ${userRoomsSnapshot.size} rooms for user: ${userId}`);

            // === user_rooms Stage管理ロジック ===
            
            // 1. stageがunreviewedでreviewDataが空でないものをreadingに変更
            const unreviewedRooms = userRoomsSnapshot.docs.filter(doc => {
              const stage = doc.data().stage;
              const reviewData = doc.data().reviewData;
              return stage === 'unreviewed' && 
                     reviewData && (
                       (reviewData.reading && Array.isArray(reviewData.reading) && reviewData.reading.length > 0) ||
                       (reviewData.listening && Array.isArray(reviewData.listening) && reviewData.listening.length > 0)
                     );
            });

            for (const roomDoc of unreviewedRooms) {
              try {
                await roomDoc.ref.update({ stage: 'reading' });
                logger.info(`Updated stage from unreviewed to reading for room: ${roomDoc.id}`);
              } catch (error) {
                logger.error(`Failed to update stage to reading for room: ${roomDoc.id}`, { error });
              }
            }

            // 2. stageがreadingでreviewDataのreadingが3個以上のものをlisteningに変更
            const readingStageRooms = userRoomsSnapshot.docs.filter(doc => doc.data().stage === 'reading');
            
            for (const roomDoc of readingStageRooms) {
              const roomData = roomDoc.data();
              const reviewData = roomData.reviewData;
              
              if (reviewData && reviewData.reading && Array.isArray(reviewData.reading) && reviewData.reading.length >= 3) {
                try {
                  await roomDoc.ref.update({ stage: 'listening' });
                  logger.info(`Updated stage from reading to listening for room: ${roomDoc.id}`);
                } catch (error) {
                  logger.error(`Failed to update stage to listening for room: ${roomDoc.id}`, { error });
                }
              }
            }

            // 3. stageがlisteningでreviewDataのlisteningが3個以上のものをcompletedに変更
            const listeningStageRooms = userRoomsSnapshot.docs.filter(doc => doc.data().stage === 'listening');
            
            for (const roomDoc of listeningStageRooms) {
              const roomData = roomDoc.data();
              const reviewData = roomData.reviewData;
              
              if (reviewData && reviewData.listening && Array.isArray(reviewData.listening) && reviewData.listening.length >= 3) {
                try {
                  await roomDoc.ref.update({ stage: 'completed' });
                  logger.info(`Updated stage from listening to completed for room: ${roomDoc.id}`);
                } catch (error) {
                  logger.error(`Failed to update stage to completed for room: ${roomDoc.id}`, { error });
                }
              }
            }
          }

          // 必要なタスクタイプを判断
          const needsGrammarList = type === 'uncreated' || (isCompleted && isCompleted.includes('grammar'));
          const needsReadingTask = type === 'uncreated' || (isCompleted && isCompleted.includes('reading'));
          const needsListeningTask = type === 'uncreated' || (isCompleted && isCompleted.includes('listening'));

          // Grammar Listを作成（必要な場合のみ）
          const grammarList = needsGrammarList ? await createGrammarList(userId, lastReviewed, plan) : [];
          
          // リーディング・リスニングタスクの作成
          let readingTask: any = null;
          let listeningTask: any = null;
          let audioUrl: string | undefined;
          
          if (needsReadingTask || needsListeningTask) {
            try {
              // 前回のuser_tasksからreadingフィールドのuser_impressionと本文を取得
              const previousTasksSnapshot = await db
                .collection('user_tasks')
                .where('userId', '==', userId)
                .orderBy('createdAt', 'desc')
                .limit(1)
                .get();
              
              let previousReadingContent: string | undefined;
              let readingUserImpression: string | undefined;
              let previousListeningContent: string | undefined;
              let listeningUserImpression: string | undefined;
              
              if (!previousTasksSnapshot.empty) {
                const previousTaskData = previousTasksSnapshot.docs[0].data();
                
                // Reading data
                const readingData = previousTaskData.reading;
                if (readingData && readingData.text) {
                  previousReadingContent = readingData.text;
                  readingUserImpression = readingData.user_impression;
                }
                
                // Listening data
                const listeningData = previousTaskData.listening;
                if (listeningData && listeningData.text) {
                  previousListeningContent = listeningData.text;
                  listeningUserImpression = listeningData.user_impression;
                }
              }
              
              // リーディング問題を作成（必要な場合のみ）
              if (needsReadingTask) {
                readingTask = await createReadingListeningTask(
                  userId,
                  plan,
                  'reading',
                  previousReadingContent,
                  readingUserImpression
                );
                
                if (readingTask) {
                  logger.info(`Created reading task for user: ${userId}`);
                } else {
                  logger.info(`Skipped reading task creation for user: ${userId} - no reading content available`);
                }
              }
              
              // リスニング問題を作成（必要な場合かつfreeプランでない場合のみ）
              if (needsListeningTask && plan !== 'free') {
                listeningTask = await createReadingListeningTask(
                  userId,
                  plan,
                  'listening',
                  previousListeningContent,
                  listeningUserImpression
                );
                
                if (listeningTask) {
                  // 音声URLを生成
                  if (listeningTask.text) {
                    audioUrl = await generateAndSaveAudio(listeningTask.text, userId);
                  }
                  logger.info(`Created listening task for user: ${userId}`);
                } else {
                  logger.info(`Skipped listening task creation for user: ${userId} - no listening content available`);
                }
              }
              
            } catch (error) {
              logger.error(`Error creating reading/listening tasks for user: ${userId}`, { error });
            }
          }
          
          
          // user_tasksの管理
          try {
            let existingTaskData: any = null;
            
            if (type === 'completed') {
              // completedユーザーの場合、既存のuser_tasksを取得
              const existingTasksSnapshot = await db
                .collection('user_tasks')
                .where('userId', '==', userId)
                .get();
              
              if (!existingTasksSnapshot.empty) {
                // 最新のタスクデータを取得
                const sortedDocs = existingTasksSnapshot.docs.sort((a, b) => {
                  const aCreatedAt = a.data().createdAt?.toDate();
                  const bCreatedAt = b.data().createdAt?.toDate();
                  return (bCreatedAt?.getTime() || 0) - (aCreatedAt?.getTime() || 0);
                });
                existingTaskData = sortedDocs[0].data();
                
                // 既存のuser_tasksを削除
                const deletePromises = existingTasksSnapshot.docs.map(doc => doc.ref.delete());
                await Promise.all(deletePromises);
                
                logger.info(`Retrieved and deleted ${existingTasksSnapshot.size} existing tasks for completed user: ${userId}`);
              }
            }
            
            // uncreatedタイプの場合、すべてのタスクが空またはnullの場合は保存しない
            if (type === 'uncreated') {
              const hasGrammarList = grammarList && grammarList.length > 0;
              const hasReadingTask = readingTask !== null;
              const hasListeningTask = listeningTask !== null;
              
              if (!hasGrammarList && !hasReadingTask && !hasListeningTask) {
                logger.info(`Skipping user_tasks creation for uncreated user: ${userId} - no tasks to save`, {
                  userId,
                  type,
                  grammarListCount: grammarList.length,
                  hasReadingTask,
                  hasListeningTask
                });
                // 次のユーザーの処理に進む
                continue;
              }
            }
            
            // 新しいuser_tasksを保存（既存データの一部置き換えまたは新規作成）
            await saveUserTasks(
              userId, 
              [], 
              grammarList, 
              readingTask, 
              listeningTask, 
              audioUrl,
              existingTaskData,
              false,
              needsGrammarList,
              needsReadingTask,
              needsListeningTask
            );
            
          } catch (error) {
            logger.error(`Error managing user tasks for user: ${userId}`, { error });
          }
          
          logger.info(`Processed user: ${userId}`, {
            type,
            plan,
            lastReviewed: lastReviewed.toISOString(),
            grammarListCount: grammarList.length,
            hasReadingTask: !!readingTask,
            hasListeningTask: !!listeningTask,
            hasAudioUrl: !!audioUrl
          });
          totalUsersProcessed++;
      } catch (error) {
        logger.error(`Error processing user: ${userId}`, {
          error: error instanceof Error ? error.message : String(error),
          userId,
        });
        }
      }
      // バッチ間で少し待機（レート制限対策）
      if (i + BATCH_SIZE < targetUsers.length) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
    logger.info('Daily tasks completed successfully', {
      totalUsersProcessed,
      executionTime: `${Date.now() - currentDate.getTime()}ms`,
    });
  } catch (error) {
    logger.error('Daily tasks failed', {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    throw error;
  }
});

/**
 * Scheduled function: Create word lists at 5 AM
 * Fetches all user_words, groups by user_id, and creates word lists based on Ebbinghaus retention
 */
export const createWordLists = onSchedule({
  schedule: '0 5 * * *', // 毎日午前5時に実行
  timeZone: 'Asia/Tokyo', // 日本時間
  memory: '1GiB',
  timeoutSeconds: 1800, // 30分のタイムアウト（最大値）
}, async (event) => {
  const currentDate = new Date();
  logger.info('Word lists creation started', { timestamp: currentDate.toISOString() });

  try {
    // user_wordsを一括取得
    const userWordsSnapshot = await db.collection('user_words').get();
    
    if (userWordsSnapshot.empty) {
      logger.info('No user_words found in the database');
      return;
    }

    logger.info(`Found ${userWordsSnapshot.size} user_words to process`);

    // user_idごとにグループ分け
    const wordsByUserId = new Map<string, any[]>();
    
    userWordsSnapshot.docs.forEach(doc => {
      const wordData = doc.data();
      const userId = wordData.user_id;
      
      if (userId) {
        if (!wordsByUserId.has(userId)) {
          wordsByUserId.set(userId, []);
        }
        wordsByUserId.get(userId)!.push({
          docId: doc.id,
          ...wordData
        });
      }
    });

    logger.info(`Grouped words for ${wordsByUserId.size} users`);

    // 各ユーザーごとに処理
    let totalUsersProcessed = 0;
    const userIds = Array.from(wordsByUserId.keys());

    for (const userId of userIds) {
      try {
        const userWords = wordsByUserId.get(userId) || [];
        logger.info(`Processing word list for user: ${userId}`, {
          userId,
          wordsCount: userWords.length
        });

        // 復習が必要な単語を収集
        const lowRetentionWordIds: WordListItem[] = [];

        for (const wordData of userWords) {
          const wordId = wordData.docId;
          const dictionaryWordId = wordData.word_id;

          // created_at を Date オブジェクトに変換
          const createdAt = wordData.created_at?.toDate();
          if (!createdAt) {
            logger.warn(`No created_at found for word: ${wordId}, skipping`);
            continue;
          }

          // isCorrectData から Review 配列を構築
          const reviewHistory: Review[] = [];
          if (wordData.isCorrectData && Array.isArray(wordData.isCorrectData)) {
            for (const correctData of wordData.isCorrectData) {
              if (correctData.isCorrect !== undefined && correctData.timestamp) {
                reviewHistory.push({
                  isCorrect: correctData.isCorrect,
                  timestamp: correctData.timestamp.toDate(),
                });
              }
            }
          }

          // 復習が必要かどうかを判定
          const shouldReview = calculateEbbinghausRetention(
            currentDate,
            createdAt,
            reviewHistory
          );

          // 復習が必要な場合、辞書から単語情報を取得して配列に追加
          if (shouldReview && dictionaryWordId) {
            try {
              const dictionaryDoc = await db.collection('dictionary').doc(dictionaryWordId).get();
              if (dictionaryDoc.exists) {
                const dictionaryData = dictionaryDoc.data();
                // meanings配列のdefinitionのみ抽出
                const meanings: string[] = [];
                if (dictionaryData?.meanings && Array.isArray(dictionaryData.meanings)) {
                  for (const meaningObj of dictionaryData.meanings) {
                    if (typeof meaningObj.definition === 'string') {
                      meanings.push(meaningObj.definition);
                    }
                  }
                }
                lowRetentionWordIds.push({
                  word: dictionaryData?.word || '',
                  meaning: meanings.length > 0 ? meanings : [''],
                  id: wordId // user_wordsコレクションのid
                });
              }
            } catch (error) {
              logger.warn(`Failed to fetch dictionary data for word_id: ${dictionaryWordId}`, { error });
            }
          }

          logger.info(`Word review status calculated`, {
            userId,
            wordId,
            dictionaryWordId,
            createdAt: createdAt.toISOString(),
            reviewCount: reviewHistory.length,
            shouldReview: shouldReview,
          });
        }

        logger.info(`Word list created for user: ${userId}`, {
          userId,
          totalWords: userWords.length,
          reviewNeededWords: lowRetentionWordIds.length
        });

        // user_tasksに保存（既存があればword_listを更新、なければ新規作成）
        const existingTasksSnapshot = await db
          .collection('user_tasks')
          .where('userId', '==', userId)
          .get();

        if (!existingTasksSnapshot.empty) {
          // 既存のuser_tasksがある場合、word_listを更新
          const updatePromises = existingTasksSnapshot.docs.map(doc => 
            doc.ref.update({ 
              word_list: lowRetentionWordIds 
            })
          );
          await Promise.all(updatePromises);
          
          logger.info(`Updated word_list for existing user_tasks: ${userId}`, {
            userId,
            tasksUpdated: existingTasksSnapshot.size,
            wordListCount: lowRetentionWordIds.length
          });
        } else {
          // 既存のuser_tasksがない場合、新規作成
          const taskDate = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
          const newTask = {
            userId,
            date: taskDate,
            createdAt: new Date(),
            word_list: lowRetentionWordIds,
            grammar_list: [],
            isCompleted: [],
            answers: {},
          };
          
          await db.collection('user_tasks').add(newTask);
          
          logger.info(`Created new user_tasks with word_list: ${userId}`, {
            userId,
            taskDate,
            wordListCount: lowRetentionWordIds.length
          });
        }

        totalUsersProcessed++;

      } catch (error) {
        logger.error(`Error processing word list for user: ${userId}`, {
          error: error instanceof Error ? error.message : String(error),
          userId,
        });
      }
    }

    logger.info('Word lists creation completed successfully', {
      totalUsersProcessed,
      executionTime: `${Date.now() - currentDate.getTime()}ms`,
    });

  } catch (error) {
    logger.error('Word lists creation failed', {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    throw error;
  }
}); 