import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

interface UserUpdateData {
  plan: string;
  purchase_data?: string[];
  [key: string]: any;
}

export const syncRevenueCatSubscription = onDocumentWritten(
  {
    document: "subscriptions/{subId}",
    region: "us-central1",
  },
  async (event) => {
    const change = event.data;
    const context = event.params;
    
    if (!change) {
      logger.warn("Change data is undefined");
      return null;
    }
    
    const { subId } = context;
    const userId = subId
    const userRef = db.collection("users").doc(userId);

    logger.info(`🔄 [${userId}] Subscription change detected`);

    if (!change.after.exists) {
      logger.info(`🗑️ [${userId}] Subscription document deleted`);
      
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        logger.warn(`⚠️ [${userId}] User document does not exist, skipping plan update`);
        return null;
      }
      
      logger.info(`📉 [${userId}] Setting plan to 'free' due to subscription deletion`);
      const updateData: UserUpdateData = { 
        plan: "free",
      };
      await userRef.update(updateData);
      return null;
    }

    const subData = change.after.data();
    
    if (!subData) {
      logger.warn(`⚠️ [${userId}] Subscription data is null`);
      return null;
    }

    logger.info(`📋 [${userId}] Subscription data:`, {
      productId: subData.product_id,
      isActive: subData.is_active,
      expiresDate: subData.expires_date?.toDate?.()?.toISOString() || 'unknown'
    });

    let newPlan = "";

    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      logger.warn(`⚠️ [${userId}] User document does not exist, skipping subscription sync`);
      return null;
    }
    
    const userData = userDoc.data();
    let purchaseData = userData?.purchase_data || [];

    const previousData = change.before.exists ? change.before.data() : null;
    let updatedPurchaseData: string[] | null = null;
    
    if (subData.subscriptions) {
      for (const [productId, currentSub] of Object.entries(subData.subscriptions) as [string, any][]) {
        const previousSub = previousData?.subscriptions?.[productId];
        
        if (currentSub) {
          const isNewPurchase = !previousSub;
          const purchaseDateChanged = !previousSub || currentSub.purchase_date !== previousSub.purchase_date;
          const expiresDateChanged = !previousSub || currentSub.expires_date !== previousSub.expires_date;
          
          if (isNewPurchase || (purchaseDateChanged && expiresDateChanged)) {
            const purchaseKey = `${productId}_${currentSub.purchase_date}`;
            
            if (purchaseData.includes(purchaseKey)) {
              logger.info(`⚠️ [${userId}] Purchase already processed: ${purchaseKey}, skipping`);
              continue; 
            }
            const currentTime = new Date();
            const oneHourAgo = new Date(currentTime.getTime() - 60 * 60 * 1000);
            const expiresDate = new Date(currentSub.expires_date);
            
            if (expiresDate < oneHourAgo) {
              logger.info(`⚠️ [${userId}] Expires date (${expiresDate.toISOString()}) is more than 1 hour in the past, skipping plan update for ${productId}`);
            } else {
              if (productId.includes("pro")) {
                newPlan = "pro";
                logger.info(`✅ [${userId}] Plan set to 'pro' based on product: ${productId}`);
              } else if (productId.includes("adfree")) {
                newPlan = "standard";
                logger.info(`✅ [${userId}] Plan set to 'standard' based on product: ${productId}`);
              }
            }
            
            purchaseData.push(purchaseKey);
            updatedPurchaseData = purchaseData;
          }
        }
      }
    }

    // データベース更新
    try {
      if (newPlan.length === 0) {
        logger.info(`ℹ️ [${userId}] No new active plan detected, skipping update`);
        return null;
      }

      const updateData: UserUpdateData = { 
        plan: newPlan,
      };

      if (updatedPurchaseData !== null) {
        updateData.purchase_data = updatedPurchaseData;
        logger.info(`📝 [${userId}] Updated purchase_data with ${updatedPurchaseData.length} entries`);
      }

      await userRef.update(updateData);
      
      const statusMessage = [
        `plan to '${newPlan}'`,
        updatedPurchaseData ? `purchase_data (${updatedPurchaseData.length} entries)` : null,
      ].filter(Boolean).join(', ');
      
      logger.info(`🎉 [${userId}] Successfully updated ${statusMessage}`);
    } catch (error) {
      logger.error(`❌ [${userId}] Failed to update user data:`, error);
      throw error;
    }

    return null;
  }
);
