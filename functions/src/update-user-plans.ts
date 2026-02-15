import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

// Firebase Admin初期化（既に初期化されている場合はスキップ）
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();

// Subscription entitlements interface
interface EntitlementData {
  expires_date: string; // ISO 8601形式 例: "2025-08-02T05:27:14Z"
  grace_period_expires_date: string | null;
  product_identifier: string;
  purchase_date: string; // ISO 8601形式 例: "2025-08-02T04:27:14Z"
}

interface SubscriptionData {
  entitlements?: {
    adfree?: EntitlementData;
    pro?: EntitlementData;
  };
  [key: string]: any;
}

/**
 * Scheduled function: Update user plans based on subscription status
 * Runs daily at 0:00 UTC to check subscription expiration and update user plans
 */
export const updateUserPlans = onSchedule({
  schedule: '0 0 * * *', // 毎日午前0時に実行（UTC）
  timeZone: 'UTC', // 世界標準時
  memory: '256MiB',
  timeoutSeconds: 300, // 5分のタイムアウト
}, async (event) => {
  const currentTime = new Date();
  logger.info('🔄 User plan update started', { 
    timestamp: currentTime.toISOString() 
  });

  try {
    // subscriptionsコレクションの全ドキュメントを取得
    const subscriptionsSnapshot = await db.collection('subscriptions').get();
    
    if (subscriptionsSnapshot.empty) {
      logger.info('📭 No subscription documents found');
      return;
    }

    logger.info(`📊 Processing ${subscriptionsSnapshot.size} subscription documents`);

    let processedCount = 0;
    let updatedCount = 0;
    let errorCount = 0;

    // 各subscriptionドキュメントを処理
    for (const subscriptionDoc of subscriptionsSnapshot.docs) {
      const userId = subscriptionDoc.id; // subscriptions/{uid} 形式
      const subscriptionData = subscriptionDoc.data() as SubscriptionData;

      try {
        processedCount++;
        
        // entitlementsフィールドを取得
        const entitlements = subscriptionData.entitlements;
        
        if (!entitlements) {
          logger.info(`📋 No entitlements found for user: ${userId}`);
          // entitlementsが存在しない場合、プランをfreeに設定
          await updateUserPlan(userId, 'free');
          updatedCount++;
          continue;
        }

        // 現在のプランを決定
        let newPlan = 'free';
        let planDetails = '';

        // proの確認（最優先）
        if (entitlements.pro && entitlements.pro.expires_date) {
          try {
            const proExpiresDate = new Date(entitlements.pro.expires_date);
            
            // 不正な日付チェック
            if (isNaN(proExpiresDate.getTime())) {
              logger.warn(`⚠️ Invalid pro expires_date for user: ${userId}`, {
                expiresDateString: entitlements.pro.expires_date
              });
            } else {
              const isProActive = proExpiresDate > currentTime;
              
              logger.debug(`📋 Pro check for user: ${userId}`, {
                expiresDateString: entitlements.pro.expires_date,
                expiresDate: proExpiresDate.toISOString(),
                currentTime: currentTime.toISOString(),
                isActive: isProActive
              });
              
              if (isProActive) {
                newPlan = 'pro';
                planDetails = `Pro expires: ${proExpiresDate.toISOString()}`;
              }
            }
          } catch (error) {
            logger.error(`❌ Error parsing pro expires_date for user: ${userId}`, {
              expiresDateString: entitlements.pro.expires_date,
              error: error instanceof Error ? error.message : String(error)
            });
          }
        }

        // adfreeの確認（proがactiveでない場合のみ）
        if (newPlan === 'free' && entitlements.adfree && entitlements.adfree.expires_date) {
          try {
            const adfreeExpiresDate = new Date(entitlements.adfree.expires_date);
            
            // 不正な日付チェック
            if (isNaN(adfreeExpiresDate.getTime())) {
              logger.warn(`⚠️ Invalid adfree expires_date for user: ${userId}`, {
                expiresDateString: entitlements.adfree.expires_date
              });
            } else {
              const isAdfreeActive = adfreeExpiresDate > currentTime;
              
              logger.debug(`📋 Adfree check for user: ${userId}`, {
                expiresDateString: entitlements.adfree.expires_date,
                expiresDate: adfreeExpiresDate.toISOString(),
                currentTime: currentTime.toISOString(),
                isActive: isAdfreeActive
              });
              
              if (isAdfreeActive) {
                newPlan = 'adfree';
                planDetails = `Adfree expires: ${adfreeExpiresDate.toISOString()}`;
              }
            }
          } catch (error) {
            logger.error(`❌ Error parsing adfree expires_date for user: ${userId}`, {
              expiresDateString: entitlements.adfree.expires_date,
              error: error instanceof Error ? error.message : String(error)
            });
          }
        }

        // usersコレクションのplanフィールドを更新
        await updateUserPlan(userId, newPlan);
        updatedCount++;

        logger.info(`✅ User plan updated`, {
          userId,
          newPlan,
          planDetails: planDetails || 'No active subscription',
          currentTime: currentTime.toISOString()
        });

      } catch (error) {
        errorCount++;
        logger.error(`❌ Error processing user: ${userId}`, {
          error: error instanceof Error ? error.message : String(error),
          userId
        });
      }
    }

    logger.info('🎉 User plan update completed', {
      totalProcessed: processedCount,
      totalUpdated: updatedCount,
      totalErrors: errorCount,
      executionTime: `${Date.now() - currentTime.getTime()}ms`
    });

    // ad_viewsが10ではないユーザーを取得して10に戻す
    await resetAdViewsToTen();

  } catch (error) {
    logger.error('💥 User plan update failed', {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined
    });
    throw error;
  }
});

/**
 * ad_viewsが10ではないユーザーを取得して10に戻す関数
 */
async function resetAdViewsToTen(): Promise<void> {
  try {
    logger.info('🔄 Starting ad_views reset process');
    
    // ad_viewsが10ではないユーザーを取得
    const usersSnapshot = await db.collection('users')
      .where('ad_views', '!=', 10)
      .get();
    
    if (usersSnapshot.empty) {
      logger.info('📭 No users found with ad_views != 10');
      return;
    }
    
    logger.info(`📊 Found ${usersSnapshot.size} users with ad_views != 10`);
    
    let resetCount = 0;
    let errorCount = 0;
    
    // 各ユーザーのad_viewsを10に戻す
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const currentAdViews = userData.ad_views;
      
      try {
        await db.collection('users').doc(userId).update({
          ad_views: 10
        });
        
        resetCount++;
        logger.info(`✅ Reset ad_views for user: ${userId}`, {
          userId,
          previousAdViews: currentAdViews,
          newAdViews: 10
        });
        
      } catch (error) {
        errorCount++;
        logger.error(`❌ Failed to reset ad_views for user: ${userId}`, {
          error: error instanceof Error ? error.message : String(error),
          userId,
          currentAdViews
        });
      }
    }
    
    logger.info('🎉 Ad views reset completed', {
      totalFound: usersSnapshot.size,
      totalReset: resetCount,
      totalErrors: errorCount
    });
    
  } catch (error) {
    logger.error('💥 Ad views reset failed', {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined
    });
    throw error;
  }
}

/**
 * usersコレクションのplanフィールドを更新する関数
 */
async function updateUserPlan(userId: string, plan: string): Promise<void> {
  try {
    const userRef = db.collection('users').doc(userId);
    
    // ユーザードキュメントが存在するか確認
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      logger.warn(`⚠️ User document not found: ${userId}`);
      return;
    }

    // planフィールドを更新
    await userRef.update({
      plan: plan,
      plan_updated_at: new Date()
    });

    logger.debug(`📝 Plan updated for user: ${userId} -> ${plan}`);
  } catch (error) {
    logger.error(`❌ Failed to update plan for user: ${userId}`, {
      error: error instanceof Error ? error.message : String(error),
      userId,
      plan
    });
    throw error;
  }
}