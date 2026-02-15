import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/admob_service.dart';
import '../widgets/paywall_widget.dart';
import 'ai_waiting_review_page.dart';

class ConversationPage extends StatefulWidget {
  final String roomId;
  final String title;

  const ConversationPage({
    super.key,
    required this.roomId,
    required this.title,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  String _userPlan = 'free';
  bool _removeAds = false;
  
  // RevenueCat関連
  Offering? _upgradeDiscountOffering;
  Offering? _defaultOffering;
  
  // バナー広告
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  
  // インタースティシャル広告
  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;
  
  // メッセージストリーム
  late Stream<QuerySnapshot> _messagesStream;
  
  // 前回のメッセージ数を追跡
  int _previousMessageCount = 0;
  
  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // メッセージストリームを初期化
  void _initializeMessagesStream() {
    _messagesStream = FirebaseFirestore.instance
        .collection('messages')
        .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .where('room_id', isEqualTo: widget.roomId)
        .orderBy('created_at', descending: false)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _initializeMessagesStream();
    _loadUserPlan();
    _loadOfferings();
    _loadBannerAd();
    _loadInterstitialAd();
  }



  // ユーザーのプラン情報を読み込み（モデル表示は廃止）
  Future<void> _loadUserPlan() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final data = userDoc.data();
          final plan = data?['plan'] ?? 'free';
          final removeAds = data?['remove_ads'] ?? false;
          setState(() {
            _userPlan = plan;
            _removeAds = removeAds;
          });
        } else {
          setState(() {
            _userPlan = 'free';
            _removeAds = false;
          });
        }
      } else {
        setState(() {
          _userPlan = 'free';
          _removeAds = false;
        });
      }
    } catch (e) {
      // エラーが発生してもデフォルトのfreeプランを使用
      setState(() {
        _userPlan = 'free';
        _removeAds = false;
      });
    }
  }
  
  /// RevenueCatのOfferingsを取得し、upgrade_discountとdefault offeringを探す
  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final upgradeDiscountOffering = offerings.all['upgrade_discount'];
      final defaultOffering = offerings.current;
      
      if (mounted) {
        setState(() {
          _upgradeDiscountOffering = upgradeDiscountOffering;
          _defaultOffering = defaultOffering;
        });
      }
    } catch (e) {
      print('Failed to load offerings: $e');
    }
  }

  void _loadBannerAd() async {
    final ad = await AdMobService.createBannerAd(
      onAdLoaded: () {
        if (!mounted) return;
        setState(() {
          _isBannerAdReady = true;
        });
      },
      onAdFailedToLoad: (error) {
        // 失敗時は破棄して非表示
        _bannerAd?.dispose();
        _bannerAd = null;
        if (!mounted) return;
        setState(() {
          _isBannerAdReady = false;
        });
      },
    );

    if (ad != null) {
      _bannerAd = ad..load();
    }
  }

  void _loadInterstitialAd() async {
    await AdMobService.createInterstitialAd(
      onAdLoaded: (ad) {
        _interstitialAd = ad;
        _isInterstitialReady = true;
      },
      onAdFailedToLoad: (_) {
        _interstitialAd?.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
      },
    );
  }

  void _showInterstitialIfReady() {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _isInterstitialReady = false;
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          _isInterstitialReady = false;
          _loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    }
  }

  

  // 安全な型変換メソッド
  Map<String, dynamic> _convertToMap(dynamic data) {
    if (data == null) {
      return <String, dynamic>{};
    }
    
    if (data is Map<String, dynamic>) {
      return data;
    }
    
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    
    // その他の場合は空のマップを返す
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 戻る時にtrueを返す（チュートリアルトリガー用）
        Navigator.pop(context, true);
        return false; // WillPopScopeの処理を止める（すでにpopしたため）
      },
      child: GestureDetector(
        onTap: () {
          // キーボード以外の部分をタップしたらフォーカスを外してキーボードを閉じる
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: AppBar(
            title: Text(
              widget.title,
              style: const TextStyle(fontSize: 16, color: Colors.black),
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black),
          ),
        ),
        body: Column(
          children: [
            // メッセージリスト
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('エラーが発生しました: ${snapshot.error}'),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final messages = snapshot.data?.docs ?? [];

                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        '💬 会話を始めましょう！',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    );
                  }



                  // 新しいメッセージが追加された場合のみスクロール処理
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (messages.isNotEmpty && messages.length > _previousMessageCount) {
                      final lastMessage = messages.last.data() as Map<String, dynamic>;
                      if (lastMessage['role'] == 'model' && _scrollController.hasClients) {
                        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                      }
                      _previousMessageCount = messages.length;
                    } else if (messages.length != _previousMessageCount) {
                      // メッセージ数が変わった場合は更新（削除の場合など）
                      _previousMessageCount = messages.length;
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + (_shouldShowUpgradeWidget(messages) ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length) {
                        // アップグレード誘導ウィジェットを表示
                        return _buildUpgradePromptWidget();
                      }
                      final message = messages[index].data() as Map<String, dynamic>;
                      return _buildMessageBubble(message);
                    },
                  );
                },
              ),
            ),

            // メッセージ入力欄
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(0, -2),
                    blurRadius: 4,
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: '質問を入力...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _isSending
                        ? null
                        : () {
                            if (_messageController.text.trim().isNotEmpty) {
                              _sendMessage(_messageController.text.trim());
                            }
                          },
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                                              : Icon(
                            Icons.send,
                            color: Theme.of(context).primaryColor,
                          ),
                  ),
                ],
              ),
            ),
            if (_bannerAd != null && _isBannerAdReady)
              Container(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                alignment: Alignment.center,
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
        ),
      ),
    );
  }

  

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final bool isUser = message['role'] == 'user';
    final String content = message['content'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.smart_toy,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isUser 
                    ? MediaQuery.of(context).size.width * 0.75
                    : MediaQuery.of(context).size.width * 0.9,
              ),
              padding: EdgeInsets.all(isUser ? 12 : 8),
              decoration: BoxDecoration(
                color: isUser 
                    ? Theme.of(context).primaryColor 
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                  bottomLeft: !isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
              ),
              child: isUser
                  ? Text(
                      content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    )
                  : MarkdownBody(
                      data: content,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        code: TextStyle(
                          backgroundColor: Colors.grey.shade300,
                          fontSize: 14,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String content) async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('❌ ログインが必要です');
        return;
      }

      // メッセージをFirestoreに保存
      await FirebaseFirestore.instance.collection('messages').add({
        'role': 'user',
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'content': content,
        'room_id': widget.roomId,
      });

      // テキストフィールドをクリア
      _messageController.clear();
      
      // テキストフィールドのフォーカスを外す
      FocusScope.of(context).unfocus();

      try {
        final qs = await FirebaseFirestore.instance
            .collection('messages')
            .where('user_id', isEqualTo: user.uid)
            .where('room_id', isEqualTo: widget.roomId)
            .get();
        final count = qs.docs.length;
        if (count % 6 == 5) {
          _showInterstitialIfReady();
        }
      } catch (_) {
        // カウント失敗時はスキップ
      }

      setState(() {
        _isSending = false;
      });

      // 復習ページへ遷移
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AiWaitingReviewPage(
              roomId: widget.roomId,
              title: widget.title,
              fromConversation: true,
            ),
          ),
        );
      }

      // AI応答生成（fire-and-forget）
      _callGenerateResponse();

    } catch (e) {
      _showMessage('❌ メッセージの送信でエラーが発生しました: $e');
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _callGenerateResponse() async {
    try {
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('generateResponse');
      
      final result = await callable.call({
        'room_id': widget.roomId,
      });
      
      // 成功時のログ（必要に応じて）
      final responseData = _convertToMap(result.data);
      if (responseData['success'] == true) {
        // AI応答が正常に生成された
      }
    } on FirebaseFunctionsException catch (_) {
      // 認証エラーやその他のFirebase Functionsエラー
      // ユーザー体験を阻害しないように続行
    } catch (_) {
      // その他のエラーが発生してもユーザー体験を阻害しないように続行
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // アップグレード誘導ウィジェットのタイトルを取得
  String _getUpgradeTitle() {
    switch (_userPlan) {
      case 'free':
        return '現在最も安価なAIモデルを使用しています';
      case 'pro':
        return 'AIの解答はいかがでしたか？';
      default:
        return 'AIの解答はいかがでしたか？';
    }
  }

  // アップグレード誘導ウィジェットの説明文を取得
  String _getUpgradeDescription() {
    switch (_userPlan) {
      case 'free' || 'standard':
        return '↓↓ 賢いAIモデルに切り替えて理解をさらに深めよう';
      default:
        return '↓↓ 賢いAIモデルに切り替えて解説を得ましょう！';
    }
  }

  // アップグレード誘導ウィジェットを表示すべきかを判定
  bool _shouldShowUpgradeWidget(List<QueryDocumentSnapshot> messages) {
    // プランがproの場合は表示しない
    if (_userPlan == 'pro') {
      return false;
    }
    
    // メッセージがない場合は表示しない
    if (messages.isEmpty) {
      return false;
    }
    
    // 最新のメッセージのroleがmodelかどうかを確認
    final lastMessage = messages.last.data() as Map<String, dynamic>;
    return lastMessage['role'] == 'model';
  }

  // アップグレード誘導ウィジェットをビルド
  Widget _buildUpgradePromptWidget() {
    return Container(
      margin: const EdgeInsets.only(top: 12, left: 4, right: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 16,
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                _getUpgradeTitle(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _getUpgradeDescription(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              // remove_adsがtrueの場合はupgrade_discount、それ以外はdefault
              final Offering? targetOffering = _removeAds
                  ? _upgradeDiscountOffering
                  : _defaultOffering;
              
              if (targetOffering != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaywallPage(
                      offering: targetOffering,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('プラン情報の読み込み中です。しばらく待ってから再度お試しください。'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'プランを見る',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }
} 