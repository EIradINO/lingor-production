import {onCall} from "firebase-functions/v2/https"; // onRequestからonCallに変更
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {TextToSpeechClient} from "@google-cloud/text-to-speech";
import {VertexAI} from "@google-cloud/vertexai";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import ffmpeg from "fluent-ffmpeg";

// Firebase Admin初期化（必要に応じて）
if (!admin.apps.length) {
  admin.initializeApp();
}

// Google Cloud Text-to-Speech Client
const ttsClient = new TextToSpeechClient();

// Vertex AI設定
const vertex_ai = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT || "lingosavor",
  location: "us-central1",
});

const gemini25FlashModel = vertex_ai.preview.getGenerativeModel({
  model: "gemini-2.5-flash-lite"
});

// Firebase Storageの音声ファイルからタイムスタンプ付きJSON生成関数
async function generateTimestampedSentencesFromAudio(audioStorageUri: string): Promise<Array<{timestamp: string, sentence: string}>> {
  try {
    // 完全なGS URIを構築（Gemini APIに必要）
    const fullGsUri = `gs://lingosavor.firebasestorage.app/${audioStorageUri}`;
    
    // ファイル拡張子からMIMEタイプを決定
    const ext = path.extname(audioStorageUri).toLowerCase();
    let mimeType: string;
    if (ext === '.mp3') mimeType = 'audio/mpeg';
    else if (ext === '.wav') mimeType = 'audio/wav';
    else if (ext === '.m4a') mimeType = 'audio/mp4';
    else throw new Error('対応していない音声ファイル形式です（mp3、wav、m4aのみ対応）');
    
    const prompt = `この音声ファイルを、ミリ秒感覚のタイムスタンプ付きで書き起こしてください。
    以下のようなJSON形式で返してください（他の説明は不要）:
    [
      {"timestamp": "00:03:834", "sentence": "最初の文"},
      {"timestamp": "00:08:123", "sentence": "2番目の文"},
      ...
    ]`;

    const result = await gemini25FlashModel.generateContent({
      contents: [{
        role: 'user',
        parts: [
          {
            fileData: {
              mimeType: mimeType,
              fileUri: fullGsUri // 完全なGS URIを使用
            }
          },
          {
            text: prompt
          }
        ],
      }],
      generationConfig: {
        audioTimestamp: true,
      },
    });
    
    const response = result.response.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!response) {
      throw new Error("No response from Gemini for audio timestamp generation");
    }
    
    const jsonMatch = response.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    } else {
      throw new Error("No valid JSON found in audio timestamp response");
    }
  } catch (error) {
    logger.warn("Error in audio timestamp generation:", error);
    throw error;
  }
}

// タイムスタンプ文字列を秒数に変換する関数（ミリ秒感覚のみ対応）
function timestampToSeconds(timestamp: string): number {
  const parts = timestamp.split(':');
  
  if (parts.length === 3) {
    // MM:SS:mmm形式（例: "00:03:834" -> 3.834秒）
    const minutes = parseInt(parts[0]);
    const seconds = parseInt(parts[1]);
    const milliseconds = parseInt(parts[2]);
    return minutes * 60 + seconds + milliseconds / 1000;
  }
  
  throw new Error(`Invalid timestamp format: ${timestamp} (only MM:SS:mmm format supported, e.g., "00:03:834")`);
}

// 沈黙音声を生成する関数
async function generateSilence(durationSeconds: number, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    ffmpeg()
      .input('anullsrc=channel_layout=mono:sample_rate=44100')
      .inputFormat('lavfi')
      .duration(durationSeconds)
      .audioCodec('aac')
      .audioFrequency(44100)
      .on('end', () => {
        logger.info(`Generated silence: ${durationSeconds}s at ${outputPath}`);
        resolve();
      })
      .on('error', (err: any) => {
        logger.error(`Error generating silence: ${err.message}`);
        reject(err);
      })
      .save(outputPath);
  });
}

// 音声ファイルを指定された時間範囲で切り出す関数
async function extractAudioSegment(
  inputPath: string,
  startSeconds: number,
  endSeconds: number,
  outputPath: string
): Promise<void> {
  return new Promise((resolve, reject) => {
    const duration = endSeconds - startSeconds;
    
    ffmpeg(inputPath)
      .seekInput(startSeconds)
      .duration(duration)
      .audioCodec('aac')
      .audioFrequency(44100)
      .on('end', () => {
        logger.info(`Extracted audio segment: ${startSeconds}s-${endSeconds}s to ${outputPath}`);
        resolve();
      })
      .on('error', (err: any) => {
        logger.error(`Error extracting audio segment: ${err.message}`);
        reject(err);
      })
      .save(outputPath);
  });
}

// 複数の音声ファイルを連結する関数
async function concatenateAudioFiles(inputPaths: string[], outputPath: string): Promise<void> {
  // concat demuxer用のリストファイルを作成
  const listPath = path.join(os.tmpdir(), `concat_list_${Date.now()}.txt`);
  const listContent = inputPaths.map(p => `file '${p}'`).join('\n');
  fs.writeFileSync(listPath, listContent);

  return new Promise((resolve, reject) => {
    ffmpeg()
      .input(listPath)
      .inputOptions(['-f', 'concat', '-safe', '0'])
      .audioCodec('aac')
      .audioFrequency(44100)
      .on('end', () => {
        logger.info(`Concatenated ${inputPaths.length} audio files to ${outputPath}`);
        try { fs.unlinkSync(listPath); } catch (_) { /* ignore */ }
        resolve();
      })
      .on('error', (err: any) => {
        logger.error(`Error concatenating audio files: ${err.message}`);
        try { fs.unlinkSync(listPath); } catch (_) { /* ignore */ }
        reject(err);
      })
      .save(outputPath);
  });
}

// 音声ファイルをオーバーラッピング用に加工する関数
async function createOverlappingAudio(
  originalPath: string,
  timestampedSentences: Array<{timestamp: string, sentence: string}>,
  outputPath: string
): Promise<void> {
  const tempDir = os.tmpdir();
  const tempFiles: string[] = [];
  
  try {
    logger.info(`Starting overlapping audio creation with ${timestampedSentences.length} sentences`);
    
    // 各セグメントを処理
    for (let i = 0; i < timestampedSentences.length; i++) {
      const currentSentence = timestampedSentences[i];
      const nextSentence = timestampedSentences[i + 1];
      
      const startSeconds = timestampToSeconds(currentSentence.timestamp);
      const endSeconds = nextSentence ? timestampToSeconds(nextSentence.timestamp) : null;
      
      // 音声セグメントを切り出し
      const segmentPath = path.join(tempDir, `segment_${i}.m4a`);
      
      if (endSeconds !== null) {
        // 次の文があるので、そこまでの区間を切り出し
        await extractAudioSegment(originalPath, startSeconds, endSeconds, segmentPath);
        
        // このセグメントの長さ（沈黙時間として使用）
        const segmentDuration = endSeconds - startSeconds;
        
        // 沈黙を生成
        const silencePath = path.join(tempDir, `silence_${i}.m4a`);
        await generateSilence(segmentDuration, silencePath);
        
        tempFiles.push(segmentPath, silencePath);
      } else {
        // 最後のセグメント（終了時刻不明なので、ファイルの終わりまで）
        await new Promise<void>((resolve, reject) => {
          ffmpeg(originalPath)
            .seekInput(startSeconds)
            .audioCodec('aac')
            .audioFrequency(44100)
            .on('end', () => {
              logger.info(`Extracted final audio segment from ${startSeconds}s to end`);
              resolve();
            })
            .on('error', (err: any) => {
              logger.error(`Error extracting final audio segment: ${err.message}`);
              reject(err);
            })
            .save(segmentPath);
        });
        
        tempFiles.push(segmentPath);
      }
    }
    
    // すべてのセグメントと沈黙を連結
    await concatenateAudioFiles(tempFiles, outputPath);
    
    logger.info('Overlapping audio creation completed successfully');
    
  } catch (error) {
    logger.error('Error in createOverlappingAudio:', error);
    throw error;
  } finally {
    // 一時ファイルを削除
    tempFiles.forEach(tempFile => {
      try {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      } catch (cleanupError) {
        logger.warn(`Failed to cleanup temp file ${tempFile}:`, cleanupError);
      }
    });
  }
}

// 内部関数として使用可能な音声処理ロジック
export async function createAudioOverlapsInternal({
  audioStorageUri,
  userId,
  documentId,
}: {
  audioStorageUri: string;
  userId: string;
  documentId: string;
}): Promise<{
  success: boolean;
  documentId: string;
  originalPath: string;
  overlappingPath: string;
  timestampedSentences: Array<{timestamp: string, sentence: string}>;
}> {
  logger.info(`Starting audio overlaps creation for: ${audioStorageUri}`);

  // Firebase Storageの音声ファイルから直接タイムスタンプ付きの文生成
  const timestampedSentences = await generateTimestampedSentencesFromAudio(audioStorageUri);
  
  // オーバーラッピング音声生成のために元音声ファイルをダウンロード
  const bucket = admin.storage().bucket("lingosavor.firebasestorage.app");
  const originalFilePath = audioStorageUri; // 既にプレフィックスが削除されたパス
  const tempDir = os.tmpdir();
  const originalLocalPath = path.join(tempDir, `original_${documentId}.${originalFilePath.split('.').pop()}`);
  const overlappingLocalPath = path.join(tempDir, `overlapping_${documentId}.m4a`);
  
  // 元音声ファイルをローカルにダウンロード（オーバーラッピング音声生成用）
  await bucket.file(originalFilePath).download({destination: originalLocalPath});
  
  // オーバーラッピング用音声を生成
  await createOverlappingAudio(originalLocalPath, timestampedSentences, overlappingLocalPath);
  
  // オーバーラッピング音声をStorageにアップロード
  const overlappingStoragePath = `audios/${userId}/overlapping_${documentId}.m4a`;
  await bucket.upload(overlappingLocalPath, {
    destination: overlappingStoragePath,
    metadata: {
      contentType: 'audio/mp4',
    },
  });
  
  const overlappingGsPath = `gs://lingosavor.firebasestorage.app/${overlappingStoragePath}`;
  
  // user_audiosコレクションにデータを保存
  await admin.firestore().collection("user_audios").add({
    user_id: userId,
    document_id: documentId,
    original_path: originalFilePath, // gs://プレフィックスを削除済み
    overlapping_path: overlappingStoragePath, // gs://プレフィックスを削除した形で保存
    timestamped_sentences: timestampedSentences,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  
  // 一時ファイルを削除
  try {
    fs.unlinkSync(originalLocalPath);
    fs.unlinkSync(overlappingLocalPath);
  } catch (cleanupError) {
    logger.warn("Failed to cleanup temporary files:", cleanupError);
  }
  
  logger.info("Audio overlaps creation completed successfully");

  return {
    success: true,
    documentId: documentId,
    originalPath: audioStorageUri,
    overlappingPath: overlappingGsPath,
    timestampedSentences: timestampedSentences,
  };
}

export const textToSpeech = onCall(
  {
    timeoutSeconds: 540, // 9分のタイムアウト
    memory: "1GiB",     // 最大メモリ
  },
  async (request) => {
    try {
      const {documentId}: {documentId: string} = request.data;

      if (!documentId) {
        throw new Error("Document ID is required");
      }

      logger.info(`Starting text-to-speech for document: ${documentId}`);

      // Firestoreからドキュメント情報を取得
      const docRef = admin.firestore().collection("user_documents").doc(documentId);
      const docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        throw new Error("Document not found");
      }

      const docData = docSnapshot.data();
      if (!docData) {
        throw new Error("Document data not found");
      }

      const user_id = docData.user_id;
      const transcription = docData.transcription;

      if (!user_id) {
        throw new Error("User ID missing");
      }

      if (!transcription || transcription.trim().length === 0) {
        throw new Error("Transcription not found. Please transcribe the document first.");
      }

      // transcriptionの長さをチェック（5000字制限）
      const transcriptionLength = transcription.trim().length;
      if (transcriptionLength > 5000) {
        throw new Error(`Transcription is too long: ${transcriptionLength} characters. Maximum allowed is 5000 characters.`);
      }

      logger.info(`Retrieved transcription for text-to-speech: length=${transcriptionLength}`);

      // ユーザーのプラン情報を取得してgem消費の必要性を判定
      const userDocRef = admin.firestore().collection("users").doc(user_id);
      const userDocSnapshot = await userDocRef.get();

      if (!userDocSnapshot.exists) {
        throw new Error("User data not found");
      }

      const userData = userDocSnapshot.data();
      if (!userData) {
        throw new Error("User data not found");
      }

      const userPlan = userData.plan || 'free';
      
      // freeプランの場合はgem消費が必要
      if (userPlan === 'free') {
        // transcriptionの単語数をカウントしてgem必要量を計算（savor-document.tsと同じ方法）
        const wordCount = transcription.trim().split(/\s+/).length;
        const requiredGems = Math.ceil(wordCount / 10);
        
        logger.info(`Free plan user: Word count: ${wordCount}, Required gems: ${requiredGems}`);

        const currentGems = userData.gems || 0;

        if (currentGems < requiredGems) {
          throw new Error(`Insufficient gems: required ${requiredGems}, current ${currentGems}`);
        }

        // gemを消費
        await userDocRef.update({
          gems: admin.firestore.FieldValue.increment(-requiredGems)
        });

        logger.info(`Consumed ${requiredGems} gems for text-to-speech (free plan)`);
      } else {
        logger.info(`Premium plan user (${userPlan}): No gem consumption required`);
      }

      // Google TTSを使用してテキストを音声に変換
      const ttsRequest = {
        input: {text: transcription},
        voice: {
          languageCode: 'en-US',
          name: 'en-US-Journey-F', // 自然な英語音声
          ssmlGender: 'FEMALE' as const,
        },
        audioConfig: {
          audioEncoding: 'MP3' as const,
          sampleRateHertz: 44100,
          speakingRate: 1.0,
          pitch: 0.0,
          volumeGainDb: 0.0,
        },
      };

      logger.info("Starting TTS generation...");
      const [ttsResponse] = await ttsClient.synthesizeSpeech(ttsRequest);

      if (!ttsResponse.audioContent) {
        throw new Error("No audio content received from TTS");
      }

      // 一時ファイルに音声を保存
      const tempDir = os.tmpdir();
      const tempAudioPath = path.join(tempDir, `tts_${documentId}.mp3`);
      fs.writeFileSync(tempAudioPath, ttsResponse.audioContent, 'binary');

      logger.info(`TTS audio saved to temporary file: ${tempAudioPath}`);

      // Firebase Storageにアップロード
      const bucket = admin.storage().bucket("lingosavor.firebasestorage.app");
      const storagePath = `audios/${user_id}/tts_${documentId}.mp3`;
      
      await bucket.upload(tempAudioPath, {
        destination: storagePath,
        metadata: {
          contentType: 'audio/mpeg',
        },
      });

      const audioStorageUri = `gs://lingosavor.firebasestorage.app/${storagePath}`;
      logger.info(`TTS audio uploaded to Storage: ${audioStorageUri}`);

      // 一時ファイルを削除
      try {
        fs.unlinkSync(tempAudioPath);
      } catch (cleanupError) {
        logger.warn("Failed to cleanup temporary TTS file:", cleanupError);
      }

      // createAudioOverlaps関数を呼び出し
      try {
        logger.info("Calling createAudioOverlaps function...");
        
        const audioResult = await createAudioOverlapsInternal({
          audioStorageUri: storagePath, // プレフィックスを削除したパスを使用
          userId: user_id,
          documentId: documentId,
        });

        logger.info("Audio overlaps processing completed successfully:", audioResult);

      } catch (audioError) {
        logger.error("Error in audio overlaps processing:", audioError);
        // 音声処理エラーは処理を停止させずに警告のみ
      }

      logger.info(`Text-to-speech completed for document: ${documentId}`);

      return {
        success: true,
        documentId: documentId,
        audioStorageUri: audioStorageUri,
        message: "Text-to-speech conversion completed successfully"
      };

    } catch (error) {
      logger.error("Error in textToSpeech function:", error);

      throw new Error(error instanceof Error ? error.message : "Unknown error");
    }
  }
); 