import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import * as admin from 'firebase-admin';

// Firebase Admin初期化（既に初期化されている場合はスキップ）
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();

// ランダムなユーザー名を生成する関数
function generateRandomUsername(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let username = '';
  for (let i = 0; i < 12; i++) {
    username += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return username;
}

/**
 * HTTPS Callable function: Create user data for new users
 * Called on every login - checks if user data exists in Firestore
 * If user_id not found in users collection, creates new user data
 */
export const createUserdata = onCall(async (request) => {
  // Check if user is authenticated
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const uid = request.auth.uid;

  try {
    // Search for user_id in users collection
    const userDoc = await db.collection("users").doc(uid).get();
    if (userDoc.exists) {
      logger.info(`User data already exists for user: ${uid}`);
      return { success: false, message: "User data already exists - existing user" };
    }

    logger.info(`User data not found for user: ${uid}, creating new user data...`);

    // Get user record from Firebase Auth
    const userRecord = await admin.auth().getUser(uid);
    const email = userRecord.email || "";
    const displayName = userRecord.displayName || "";
    const userName = generateRandomUsername();
    const createdAt = admin.firestore.FieldValue.serverTimestamp();

    // Create user document in users collection with gems field
    await db.collection("users").doc(uid).set({
      user_id: uid,
      email: email,
      display_name: displayName,
      user_name: userName,
      created_at: createdAt,
      gems: 200,
      plan: "free",
      ad_views: 10,
    });

    logger.info(`New user data created successfully for user: ${uid}`, {
      uid,
      email,
      displayName,
      userName,
    });

    return { 
      success: true, 
      message: "New user data created successfully",
      userData: {
        user_id: uid,
        email,
        display_name: displayName,
        user_name: userName,
      }
    };

  } catch (error) {
    logger.error(`Failed to create user data for user: ${uid}`, {
      error,
      uid,
    });
    throw new HttpsError("internal", "Failed to create user data");
  }
}); 