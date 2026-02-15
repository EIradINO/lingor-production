import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/admob_service.dart';
import 'dart:async';
import 'dart:math' as math;

class GemPurchaseWidget extends StatefulWidget {
  const GemPurchaseWidget({super.key});

  @override
  State<GemPurchaseWidget> createState() => _GemPurchaseWidgetState();
}

class _GemPurchaseWidgetState extends State<GemPurchaseWidget> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isLoading = true;
  bool _connectionPending = false;
  bool _isButtonTapped = false;
  
  // リワード広告関連
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  
  // ユーザーの広告視聴回数
  int _adViews = 0;
  
  // 製品ID
  static const String _kGem1000Id = 'com.lingosavor.1000gem';
  static const String _kGem5000Id = 'com.lingosavor.5000gem';
  static const String _kGem20000Id = 'com.lingosavor.20000gem';
  
  static const Set<String> _kIds = <String>{
    _kGem1000Id,
    _kGem5000Id,
    _kGem20000Id,
  };

  List<ProductDetails> _products = <ProductDetails>[];
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeStore();
    _loadRewardedAd();
    _loadUserAdViews();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }

  Future<void> _initializeStore() async {
    try {
      final bool isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        setState(() {
          _isAvailable = false;
          _isLoading = false;
        });
        return;
      }

      // 購入状態の変更を監視
      final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
      _subscription = purchaseUpdated.listen((List<PurchaseDetails> purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        _subscription.cancel();
      }, onError: (Object error) {
        print('購入ストリームエラー: $error');
      });

      // 商品情報を取得
      final ProductDetailsResponse productDetailResponse =
          await _inAppPurchase.queryProductDetails(_kIds);

      if (productDetailResponse.error != null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isAvailable = isAvailable;
        _products = productDetailResponse.productDetails;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ユーザーの広告視聴回数を読み込み
  Future<void> _loadUserAdViews() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        setState(() {
          _adViews = data?['ad_views'] ?? 0;
        });
      }
    } catch (e) {
      print('広告視聴回数読み込みエラー: $e');
    }
  }

  // リワード広告の読み込み
  void _loadRewardedAd() {
    setState(() {
      _isRewardedAdLoading = true;
    });

    AdMobService.createRewardedAd(
      onAdLoaded: (RewardedAd ad) {
        setState(() {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
        });
      },
      onAdFailedToLoad: (LoadAdError error) {
        setState(() {
          _isRewardedAdLoading = false;
        });
        print('リワード広告の読み込みエラー: $error');
      },
    );
  }

  // リワード広告の表示
  void _showRewardedAd() {
    if (_rewardedAd == null) {
      _loadRewardedAd();
      return;
    }

    // 広告表示時に全てのボタンを無効化
    setState(() {
      _isButtonTapped = true;
    });

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        print('リワード広告が表示されました');
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        // 広告終了時にボタンを再有効化
        setState(() {
          _isButtonTapped = false;
        });
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        // 広告失敗時にボタンを再有効化
        setState(() {
          _isButtonTapped = false;
        });
      },
    );

    _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _addRewardToUser(reward.amount.toInt());
        _showRewardDialog(reward);
      },
    );
  }

  // 報酬ダイアログの表示
  void _showRewardDialog(RewardItem reward) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('報酬を受け取りました！'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.diamond,
                color: Colors.amber,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                '${reward.amount} ${reward.type}を獲得しました！',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // 報酬をユーザーに追加
  Future<void> _addRewardToUser(int gems) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // add-gems Cloud Functionを呼び出し
      final callable = FirebaseFunctions.instance.httpsCallable('addGems');
      await callable.call({
        'gem': gems,
        'user_id': user.uid,
        'isAd': true,
      });

      // ad_viewsを更新し、ボタンを再有効化
      setState(() {
        _adViews = math.max(0, _adViews - 1);
        _isButtonTapped = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${gems}gemが追加されました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('報酬追加エラー: $e');
      // エラー時にボタンを再有効化
      setState(() {
        _isButtonTapped = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('報酬の追加に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _showPendingUI();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          _handleError(purchaseDetails.error!);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          _handleSuccessfulPurchase(purchaseDetails);
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
          _handlePurchaseCanceled();
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  void _showPendingUI() {
    setState(() {
      _connectionPending = true;
    });
  }

  void _handleError(IAPError error) {
    setState(() {
      _connectionPending = false;
      _isButtonTapped = false; // エラー時にボタンを再有効化
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('購入エラー: ${error.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) {
    setState(() {
      _connectionPending = false;
      _isButtonTapped = false; // 購入完了時にボタンを再有効化
    });

    // Gemを追加する処理
    _addGemsToUser(purchaseDetails.productID);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('購入が完了しました！'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handlePurchaseCanceled() {
    setState(() {
      _connectionPending = false;
      _isButtonTapped = false; // キャンセル時にボタンを再有効化
    });
  }

  Future<void> _addGemsToUser(String productId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      int gemsToAdd = 0;
      switch (productId) {
        case _kGem1000Id:
          gemsToAdd = 1000;
          break;
        case _kGem5000Id:
          gemsToAdd = 5000;
          break;
        case _kGem20000Id:
          gemsToAdd = 20000;
          break;
      }

      // addGems関数を呼び出してジェムを追加
      final callable = FirebaseFunctions.instance.httpsCallable('addGems');
      await callable.call({
        'gem': gemsToAdd,
        'user_id': user.uid,
        'isAd': false,
      });

    } catch (e) {
      print('Gem追加エラー: $e');
    }
  }

  void _buyProduct(ProductDetails productDetails) async {
    // ボタンタップ時に全てのボタンを無効化
    setState(() {
      _isButtonTapped = true;
    });
    
    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );
      await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      // キャンセル例外の場合は専用処理
      if (e.toString().contains('purchase_cancelled')) {
        _handlePurchaseCanceled();
      } else {
        // その他のエラーの場合
        setState(() {
          _connectionPending = false;
          _isButtonTapped = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('購入エラー: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  int _getGemAmount(String productId) {
    switch (productId) {
      case _kGem1000Id:
        return 1000;
      case _kGem5000Id:
        return 5000;
      case _kGem20000Id:
        return 20000;
      default:
        return 0;
    }
  }

  String _getGemTitle(String productId) {
    switch (productId) {
      case _kGem1000Id:
        return '1,000';
      case _kGem5000Id:
        return '5,000';
      case _kGem20000Id:
        return '20,000';
      default:
        return 'Unknown';
    }
  }

  MaterialColor _getCardColor(String productId) {
    switch (productId) {
      case _kGem1000Id:
        return Colors.blue;
      case _kGem5000Id:
        return Colors.purple;
      case _kGem20000Id:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // fallbackの価格を返す関数
  String _getFallbackPrice(String productId) {
    switch (productId) {
      case _kGem1000Id:
        return '¥500';
      case _kGem5000Id:
        return '¥2,000';
      case _kGem20000Id:
        return '¥5,000';
      default:
        return '¥--';
    }
  }

  // リワード広告ボタンの作成
  Widget _buildRewardButton() {
    final canShowAd = _rewardedAd != null && !_isRewardedAdLoading && _adViews > 0 && !_isButtonTapped;
    
    return GestureDetector(
      onTap: canShowAd ? _showRewardedAd : null,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isButtonTapped
                ? [Colors.grey[200]!, Colors.grey[400]!]
                : canShowAd 
                    ? [Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)]
                    : [Colors.grey[200]!, Colors.grey[400]!],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isButtonTapped
                ? Colors.grey.withOpacity(0.3)
                : canShowAd 
                    ? Colors.green
                    : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: _isRewardedAdLoading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber[600]!),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    color: _isButtonTapped 
                        ? Colors.grey[400]
                        : canShowAd ? Colors.green : Colors.grey[400],
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      text: '10',
                      style: TextStyle(
                        color: _isButtonTapped 
                            ? Colors.grey[500]
                            : canShowAd ? Colors.green : Colors.grey[500],
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      children: [
                        TextSpan(
                          text: 'gem',
                          style: TextStyle(
                            color: _isButtonTapped 
                                ? Colors.grey[500]
                                : canShowAd ? Colors.green : Colors.grey[500],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    '広告を視聴',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '($_adViews / 10)',
                    style: TextStyle(
                      color: _isButtonTapped 
                          ? Colors.grey[500]
                          : _adViews > 0 ? Colors.green : Colors.red,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGemButton(String productId, {ProductDetails? product}) {
    final amount = _getGemTitle(productId);
    final color = _getCardColor(productId);
    final price = product?.price ?? _getFallbackPrice(productId);
    final isLoading = _connectionPending;
    final canPurchase = _isAvailable && !isLoading && product != null && !_isButtonTapped;

    return GestureDetector(
        onTap: canPurchase ? () => _buyProduct(product) : null,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            gradient: _isButtonTapped
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.grey[200]!,
                      Colors.grey[400]!,
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color[50]!,
                      color[200]!,
                    ],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isButtonTapped
                  ? Colors.grey.withOpacity(0.3)
                  : color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color[600]!),
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.diamond,
                      color: canPurchase ? color[600] : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: amount,
                        style: TextStyle(
                          color: canPurchase ? color[700] : Colors.grey[500],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: 'gem',
                            style: TextStyle(
                              color: canPurchase ? color[700] : Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      price,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 100,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isAvailable) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'アプリ内課金が利用できません',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    // 商品を価格順にソート
    final sortedProducts = List<ProductDetails>.from(_products);
    sortedProducts.sort((a, b) {
      final aGems = _getGemAmount(a.id);
      final bGems = _getGemAmount(b.id);
      return aGems.compareTo(bGems);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GEMを追加',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // 2×2のグリッドレイアウト
        SizedBox(
          height: 212, // 100 * 2 + 12 (スペース)
          child: Column(
            children: [
              // 上段
              Row(
                children: [
                  // 左上：リワード広告ボタン
                  Expanded(child: _buildRewardButton()),
                  const SizedBox(width: 12),
                  // 右上：1000gem
                  Expanded(
                    child: _buildGemButton(
                      _kGem1000Id,
                      product: _products.where((p) => p.id == _kGem1000Id).firstOrNull,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 下段
              Row(
                children: [
                  // 左下：5000gem
                  Expanded(
                    child: _buildGemButton(
                      _kGem5000Id,
                      product: _products.where((p) => p.id == _kGem5000Id).firstOrNull,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 右下：20000gem
                  Expanded(
                    child: _buildGemButton(
                      _kGem20000Id,
                      product: _products.where((p) => p.id == _kGem20000Id).firstOrNull,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
