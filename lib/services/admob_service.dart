import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdMobService {
  // iOS用テスト広告ID
  static const String _testBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialAdUnitId = 'ca-app-pub-3940256099942544/4411468910';
  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/1712485313';

  // iOS用本番広告ID（実際のAdMobアカウントから取得したIDに置き換えてください）
  static const String _productionBannerAdUnitId = 'ca-app-pub-3418424283193363/4329815527';
  static const String _productionInterstitialAdUnitId = 'ca-app-pub-3418424283193363/9381796183';
  static const String _productionRewardedAdUnitId = 'ca-app-pub-3418424283193363/2311795269';

  // 現在使用する広告IDを取得（デバッグモードではテスト用ID、リリースモードでは本番用ID）
  static String get bannerAdUnitId {
    return kDebugMode ? _testBannerAdUnitId : _productionBannerAdUnitId;
  }

  static String get interstitialAdUnitId {
    return kDebugMode ? _testInterstitialAdUnitId : _productionInterstitialAdUnitId;
  }

  static String get rewardedAdUnitId {
    return kDebugMode ? _testRewardedAdUnitId : _productionRewardedAdUnitId;
  }

  /// ユーザーのプランが有料プランかどうかをチェック
  static Future<bool> _shouldShowAds() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return true; // ログインしていない場合は広告を表示
      
      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) return true; // ユーザーデータがない場合は広告を表示
      
      final Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
      final String plan = data?['plan'] ?? 'free';
      final bool removeAds = data?['remove_ads'] ?? false;
      
      // proまたはstandardプランの場合は広告を表示しない
      // remove_adsフィールドがtrueの場合も広告を表示しない
      return plan != 'pro' && plan != 'standard' && !removeAds;
    } catch (e) {
      print('プランチェックエラー: $e');
      return true; // エラーの場合は広告を表示
    }
  }

  static Future<void> initialize() async {
    // iOS専用のため、iOSの場合のみ初期化
    if (Platform.isIOS) {
      await MobileAds.instance.initialize();
    }
  }

  // バナー広告を作成（iOS専用、プランチェック付き）
  static Future<BannerAd?> createBannerAd({
    required void Function() onAdLoaded,
    required void Function(LoadAdError error) onAdFailedToLoad,
  }) async {
    if (!Platform.isIOS) {
      return null;
    }
    
    // プランチェック - 有料プランの場合は広告を表示しない
    final bool shouldShow = await _shouldShowAds();
    if (!shouldShow) {
      return null;
    }
    
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => onAdLoaded(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onAdFailedToLoad(error);
        },
      ),
    );
  }

  // インタースティシャル広告を作成（iOS専用、プランチェック付き）
  static Future<void> createInterstitialAd({
    required void Function(InterstitialAd ad) onAdLoaded,
    required void Function(LoadAdError error) onAdFailedToLoad,
  }) async {
    if (!Platform.isIOS) {
      return;
    }
    
    // プランチェック - 有料プランの場合は広告を表示しない
    final bool shouldShow = await _shouldShowAds();
    if (!shouldShow) {
      return;
    }
    
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  // リワード広告を作成（iOS専用、プランに関わらず常に表示）
  static Future<void> createRewardedAd({
    required void Function(RewardedAd ad) onAdLoaded,
    required void Function(LoadAdError error) onAdFailedToLoad,
  }) async {
    if (!Platform.isIOS) {
      return;
    }
    
    // リワード広告はプランに関わらず常に表示
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }
}
