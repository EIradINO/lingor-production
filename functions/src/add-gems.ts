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

interface AddGemsData {
  gem: number;
  user_id: string;
  isAd?: boolean;
}

/**
 * HTTPS Callable function: Add gems to a user
 * Receives gem amount and user_id, then increases the user's gems by the specified amount
 */
export const addGems = onCall(async (request) => {
  // Check if user is authenticated
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const data = request.data as AddGemsData;

  // Validate input parameters
  if (data.gem == null || data.user_id == null) {
    throw new HttpsError("invalid-argument", "gem and user_id are required");
  }

  if (typeof data.gem !== 'number' || data.gem <= 0) {
    throw new HttpsError("invalid-argument", "gem must be a positive number");
  }

  if (typeof data.user_id !== 'string' || data.user_id.trim() === '') {
    throw new HttpsError("invalid-argument", "user_id must be a non-empty string");
  }

  if (data.isAd !== undefined && typeof data.isAd !== 'boolean') {
    throw new HttpsError("invalid-argument", "isAd must be a boolean");
  }

  try {
    // Ensure gem is an integer by rounding up
    const gemToAdd = Math.ceil(data.gem);

    // Check if user exists in users collection
    const userDocRef = db.collection("users").doc(data.user_id);
    const userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      logger.error(`User not found: ${data.user_id}`);
      throw new HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data();
    const currentGems = userData?.gems || 0;
    const currentAdViews = userData?.ad_views || 0;

    // Prepare update data
    const updateData: any = {
      gems: admin.firestore.FieldValue.increment(gemToAdd)
    };

    // If isAd is true, decrement ad_views by 1
    if (data.isAd) {
      updateData.ad_views = admin.firestore.FieldValue.increment(-1);
    }

    // Update user's gems and ad_views if needed
    await userDocRef.update(updateData);

    const newGemsTotal = currentGems + gemToAdd;
    const newAdViews = data.isAd ? Math.max(0, currentAdViews - 1) : currentAdViews;

    logger.info(`Successfully added ${gemToAdd} gems to user ${data.user_id}`, {
      user_id: data.user_id,
      gems_added: gemToAdd,
      previous_gems: currentGems,
      new_gems_total: newGemsTotal,
      is_ad: data.isAd,
      previous_ad_views: currentAdViews,
      new_ad_views: newAdViews,
      requesting_user: request.auth.uid
    });

    return {
      success: true,
      message: `Successfully added ${gemToAdd} gems to user`,
      data: {
        user_id: data.user_id,
        gems_added: gemToAdd,
        previous_gems: currentGems,
        new_gems_total: newGemsTotal,
        is_ad: data.isAd,
        previous_ad_views: currentAdViews,
        new_ad_views: newAdViews
      }
    };

  } catch (error) {
    logger.error(`Failed to add gems to user: ${data.user_id}`, {
      error,
      user_id: data.user_id,
      gems_to_add: Math.ceil(data.gem),
      is_ad: data.isAd,
      requesting_user: request.auth.uid,
    });

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError("internal", "Failed to add gems to user");
  }
});
