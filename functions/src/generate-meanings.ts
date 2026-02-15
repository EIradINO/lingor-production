import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { VertexAI } from '@google-cloud/vertexai';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

// Firebase Admin初期化（既に初期化されている場合はスキップ）
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();

// Vertex AI設定
const vertex_ai = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT || "lingosavor",
  location: "us-central1",
});

const generativeModel = vertex_ai.preview.getGenerativeModel({
  model: "gemini-2.5-flash-lite",
});

// ステップ1: 基本形変換用プロンプト
const generateBaseWordPrompt = (word: string, sentence: string) => `
単語: "${word}"
文脈: "${sentence}"

この単語が変更群、非変更群のどちらに当てはまるか判断してください。

変更群:
- 所有格の名詞
- 比較級・最上級の形容詞
- 過去形の動詞
- 受動態・完了形における過去分詞
- 進行形・分詞構文における現在分詞
- 三単現のsがついている
- 複数形のsがついている

非変更群:
- 形容詞としての過去分詞・現在分詞
- 変更群に当てはまらないもの

変更群に当てはまらない場合は、必ずそのままの形を返してください。イディオムは"必ず"全体を返してください。
変更群に当てはまる場合、その原形（基本形）を返してください。イディオムの場合は変更群に当てはまる単語を原形にした上で全体を返してください。(例: "kicked off" -> "kick off")
非変更群に当てはまる場合、そのままの形を返してください。

以下のJSONスキーマに従って正確に生成してください:
{
  "base_word": "原形（基本形）の単語"
}
`;

// ステップ1: 文脈役割分析用プロンプト  
const generateContextRolePrompt = (word: string, sentence: string) => `
単語: "${word}"
文脈: "${sentence}"

以下のJSONスキーマに従って正確に生成してください:
{
  "part_of_speech": "品詞(日本語)",
  "context_role": "この単語が文の中で果たしている役割の説明を100-200字程度でしっかり骨太に行なってください（日本語）"
}
`;

// examples生成用プロンプト
const generateExamplesPrompt = (baseWord: string, meanings: any[], userWords: string[] = []) => `
以下の英単語の各意味について、実用的な例文を生成してください。

単語: "${baseWord}"
英語例文で用いる単語: ${userWords.length > 0 ? userWords.join(', ') : '特になし'}

意味一覧:
${meanings.map((meaning, index) => `${index + 1}. ${meaning.part_of_speech}: ${meaning.definition}`).join('\n')}

以下のJSONスキーマに従って正確に生成してください:
{
  "examples": [
    [
      {
        "original": "英語例文",
        "translation": "日本語訳"
      }
    ]
  ]
}

重要な指示:
1. examples配列は、各意味に対応する例文配列の配列です（List<List<例文>>形式）
2. 各意味につき2-3個の実用的な例文を生成してください
3. 「英語例文で用いる単語」が指定されている場合は、できる限りその単語を例文に含めてください
4. 例文は自然で実用的なものにしてください
5. 日本語訳は自然で理解しやすい表現にしてください
`;

// ステップ2: 詳細意味生成用プロンプト
const generateDetailedMeaningsPrompt = (baseWord: string) => `
以下の英単語について、詳細な辞書情報を生成してください。

単語: "${baseWord}"

以下のJSONスキーマに従って正確に生成してください:
{
  "word": "${baseWord}",
  "pronunciation": "発音記号",
  "meanings": [
    {
      "part_of_speech": "品詞（日本語）",
      "definition": "意味・定義（日本語）",
      "nuance": "その意味でのニュアンスや使い方の詳細説明（日本語）",
      "collocations": [
        {
          "phrase": "コロケーション",
          "translation": "日本語訳"
        }
      ],
      "synonyms": [
        {
          "word": "類義語",
          "nuance": "類義語のニュアンスの違い（日本語）"
        }
      ]
    }
  ],
  "derivatives": [
    {
      "word": "派生語",
      "part_of_speech": "品詞（日本語）",
      "translation": "日本語意味"
    }
  ],
  "etymology": "語源情報（日本語）"
}

重要な指示:
1. meanings配列にはなるべくたくさんの意味を含めてください
2. 各meaningには必ずpart_of_speechで品詞を指定してください（例：「動詞」「名詞」「形容詞」など）
3. collocationsには実際によく使われる組み合わせを3-5個含めてください
4. synonymsには主要な類義語を2-4個含め、ニュアンスの違いを説明してください
5. derivativesには関連する派生語を含めてください
6. etymologyには語源の詳細な説明を含めてください
7. すべての日本語説明は自然で理解しやすい表現にしてください
`;

// user_wordsコレクションからランダムに3つの単語を取得する関数
const getRandomUserWords = async (userId: string): Promise<string[]> => {
  try {
    const userWordsRef = db.collection('user_words');
    const querySnapshot = await userWordsRef.where('user_id', '==', userId).get();
    
    if (querySnapshot.empty) {
      logger.info(`No user words found for user: ${userId}`);
      return [];
    }
    
    // 全てのドキュメントからword_idを取得
    const wordIds: string[] = [];
    querySnapshot.forEach(doc => {
      const data = doc.data();
      if (data.word_id) {
        wordIds.push(data.word_id);
      }
    });
    
    if (wordIds.length === 0) {
      logger.info(`No valid word_ids found for user: ${userId}`);
      return [];
    }
    
    // ランダムに3つ選択（利用可能な数が3未満の場合は全て選択）
    const shuffled = wordIds.sort(() => 0.5 - Math.random());
    const selectedWordIds = shuffled.slice(0, Math.min(3, wordIds.length));
    
    logger.info(`Selected word_ids: ${selectedWordIds.join(', ')}`);
    
    // word_idに基づいてdictionaryコレクションから英単語を取得
    const words: string[] = [];
    const dictionaryRef = db.collection('dictionary');
    
    for (const wordId of selectedWordIds) {
      const docSnapshot = await dictionaryRef.doc(wordId).get();
      if (docSnapshot.exists) {
        const data = docSnapshot.data();
        if (data?.word) {
          words.push(data.word);
        }
      }
    }
    
    logger.info(`Retrieved words: ${words.join(', ')}`);
    return words;
    
  } catch (error) {
    logger.error('Error getting random user words:', error);
    return [];
  }
};

// JSONレスポンスを解析する関数（responseMimeType使用時は直接パース）
const parseJsonResponse = (response: string): any => {
  try {
    const parsed = JSON.parse(response);
    logger.info('Successfully parsed JSON response:', JSON.stringify(parsed, null, 2));
    
    // AIが配列形式で返す場合があるので、配列の場合は最初の要素を取り出す
    if (Array.isArray(parsed) && parsed.length > 0) {
      logger.info('Response is array format, extracting first element');
      return parsed[0];
    }
    
    return parsed;
  } catch (error) {
    logger.error('Failed to parse JSON response:', error);
    logger.error('Raw response:', response);
    throw new Error(`Invalid JSON response from AI: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
};

export const generateMeanings = onCall( async (request) => {
  try {
    const { data, auth } = request;
    
    // 認証済みユーザーかどうかを確認
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'この機能を利用するには認証が必要です。'
      );
    }

    const { word, sentence } = data;
    
    if (!word || typeof word !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'Invalid request: word parameter is required'
      );
    }

    if (typeof sentence !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'Invalid request: sentence parameter must be a string'
      );
    }

    logger.info(`Starting analysis for word: ${word} in sentence: ${sentence} for user: ${auth.uid}`);

    let baseWordData: any;

    // sentenceが空白の場合は分析をスキップ
    if (!sentence.trim()) {
      logger.info('Sentence is empty, skipping base word analysis...');
      baseWordData = {
        original_word: word,
        word_form: "",
        base_word: word,
        part_of_speech: "",
        context_role: ""
      };
    } else {
      // ステップ1: 基本形変換と文脈役割分析を並列実行
      logger.info('Step 1: Analyzing base word and context role in parallel...');
      
      const baseWordPrompt = generateBaseWordPrompt(word, sentence);
      const contextRolePrompt = generateContextRolePrompt(word, sentence);
      
      const baseWordRequest = {
        contents: [{ role: 'user', parts: [{ text: baseWordPrompt }] }],
        generationConfig: {
          responseMimeType: 'application/json',
        },
      };
      
      const contextRoleRequest = {
        contents: [{ role: 'user', parts: [{ text: contextRolePrompt }] }],
        generationConfig: {
          responseMimeType: 'application/json',
        },
      };
      
      // 並列実行
      const [baseWordResult, contextRoleResult] = await Promise.all([
        generativeModel.generateContent(baseWordRequest),
        generativeModel.generateContent(contextRoleRequest)
      ]);
      
      const baseWordResponse = baseWordResult.response.candidates?.[0]?.content?.parts?.[0]?.text;
      const contextRoleResponse = contextRoleResult.response.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!baseWordResponse) {
        throw new HttpsError(
          'internal',
          'No response from AI model for base word analysis'
        );
      }

      if (!contextRoleResponse) {
        throw new HttpsError(
          'internal',
          'No response from AI model for context role analysis'
        );
      }

      const baseWordResult_parsed = parseJsonResponse(baseWordResponse);
      const contextRoleData = parseJsonResponse(contextRoleResponse);
      
      // 結合したデータを作成
      baseWordData = {
        original_word: word,
        word_form: word !== baseWordResult_parsed.base_word ? word : "",
        base_word: baseWordResult_parsed.base_word,
        part_of_speech: contextRoleData.part_of_speech,
        context_role: contextRoleData.context_role
      };
    }

    const baseWord = baseWordData.base_word;

    if (!baseWord || typeof baseWord !== 'string') {
      throw new HttpsError(
        'internal',
        `Invalid base word generated: ${baseWord}`
      );
    }

    logger.info(`Base word identified: ${baseWord}`);

    // ステップ3: Firestoreのdictionaryコレクションを検索
    logger.info(`Step 3: Searching dictionary for: ${baseWord}`);
    const dictionaryRef = db.collection('dictionary');
    const querySnapshot = await dictionaryRef.where('word', '==', baseWord).limit(1).get();

    let dictionaryId: string;
    let examples: any[] = [];

    if (!querySnapshot.empty) {
      // ヒットした場合: 既存のドキュメントIDを取得
      logger.info(`Dictionary entry found for: ${baseWord}`);
      const doc = querySnapshot.docs[0];
      dictionaryId = doc.id;
      
      // 既存のdictionaryデータを取得してexamplesを生成
      const existingData = doc.data();
      if (existingData?.meanings) {
        // ユーザーの単語を取得
        const userWords = await getRandomUserWords(auth.uid);
        
        // 既存のmeaningsデータを使ってexamplesを生成
        logger.info(`Generating examples for existing dictionary entry. Meanings count: ${existingData.meanings.length}`);
        logger.info(`User words for examples: ${userWords.join(', ')}`);
        
        const examplesPrompt = generateExamplesPrompt(baseWord, existingData.meanings, userWords);
        logger.info(`Examples prompt: ${examplesPrompt.substring(0, 200)}...`);
        
        const examplesRequest = {
          contents: [{ role: 'user', parts: [{ text: examplesPrompt }] }],
          generationConfig: {
            responseMimeType: 'application/json',
          },
        };
        
        const examplesResult = await generativeModel.generateContent(examplesRequest);
        const examplesResponse = examplesResult.response.candidates?.[0]?.content?.parts?.[0]?.text;
        
        logger.info(`Examples response: ${examplesResponse}`);
        
        if (examplesResponse) {
          const examplesData = parseJsonResponse(examplesResponse);
          examples = examplesData.examples || [];
          logger.info(`Generated examples count: ${examples.length}`);
          logger.info(`Examples data: ${JSON.stringify(examples, null, 2)}`);
        } else {
          logger.warn('No examples response received');
        }
      }
    } else {
      // ヒットしなかった場合: 新しいデータを生成して保存
      logger.info(`Dictionary entry not found. Generating new entry for: ${baseWord}`);
      
      // ユーザーの単語を取得
      const userWords = await getRandomUserWords(auth.uid);
      
      const detailedPrompt = generateDetailedMeaningsPrompt(baseWord);
      
      const detailedRequest = {
        contents: [{ role: 'user', parts: [{ text: detailedPrompt }] }],
        generationConfig: {
          responseMimeType: 'application/json',
        },
      };
      
      const detailedResult = await generativeModel.generateContent(detailedRequest);
      const detailedResponse = detailedResult.response.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!detailedResponse) {
        throw new HttpsError(
          'internal',
          'No response from AI model for detailed meanings'
        );
      }

      const dictionaryData = parseJsonResponse(detailedResponse);
      
      // examples生成
      logger.info(`Generating examples for new dictionary entry. Meanings count: ${dictionaryData.meanings.length}`);
      logger.info(`User words for examples: ${userWords.join(', ')}`);
      
      const examplesPrompt = generateExamplesPrompt(baseWord, dictionaryData.meanings, userWords);
      logger.info(`Examples prompt: ${examplesPrompt.substring(0, 200)}...`);
      
      const examplesRequest = {
        contents: [{ role: 'user', parts: [{ text: examplesPrompt }] }],
        generationConfig: {
          responseMimeType: 'application/json',
        },
      };
      
      const examplesResult = await generativeModel.generateContent(examplesRequest);
      const examplesResponse = examplesResult.response.candidates?.[0]?.content?.parts?.[0]?.text;
      
      logger.info(`Examples response: ${examplesResponse}`);
      
      if (!examplesResponse) {
        throw new HttpsError(
          'internal',
          'No response from AI model for examples generation'
        );
      }
      
      const examplesData = parseJsonResponse(examplesResponse);
      examples = examplesData.examples || [];
      logger.info(`Generated examples count: ${examples.length}`);
      logger.info(`Examples data: ${JSON.stringify(examples, null, 2)}`);
      
      
      // dictionaryDataからexamplesを除去してFirestoreに保存
      const dictionaryDataForSaving = {
        ...dictionaryData,
        meanings: dictionaryData.meanings.map((meaning: any) => {
          const { examples, ...meaningWithoutExamples } = meaning;
          return meaningWithoutExamples;
        })
      };
      
      // Firestoreに保存してIDを取得
      logger.info(`Saving new dictionary entry for: ${baseWord}`);
      const docRef = await dictionaryRef.add({
        ...dictionaryDataForSaving,
        saved_users: 0,
        source: "english",
        target: "japanese",
        created_at: new Date(),
        updated_at: new Date()
      });
      dictionaryId = docRef.id;
    }

    // ステップ4: 最終的なレスポンスを構築（dictionary IDと分析データのみ）
    const finalResponse = {
      original_word: baseWordData.original_word,
      base_word: baseWordData.base_word,
      word_form: baseWordData.word_form,
      part_of_speech: baseWordData.part_of_speech,
      context_role: baseWordData.context_role,
      examples: examples, // 例文配列List<List<>>
      dictionary_id: dictionaryId
    };

    logger.info(`Final response examples count: ${examples.length}`);
    logger.info(`Final response examples structure: ${JSON.stringify(examples, null, 2)}`);
    logger.info(`Successfully generated meanings for: ${word}, dictionary ID: ${dictionaryId}`);

    return {
      success: true,
      data: finalResponse
    };

  } catch (error) {
    logger.error('Error in generateMeanings function:', error);
    
    // FirebaseFunctionsのエラーが既に投げられている場合はそのまま再スロー
    if (error instanceof HttpsError) {
      throw error;
    }
    
    throw new HttpsError(
      'internal',
      `Internal server error: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}); 