import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecondTutorialPage extends StatefulWidget {
  const SecondTutorialPage({super.key});

  @override
  State<SecondTutorialPage> createState() => _SecondTutorialPageState();
}

class _SecondTutorialPageState extends State<SecondTutorialPage> with TickerProviderStateMixin {
  int _currentMessageIndex = 0;
  int _currentPhase = 0; // 0: 初期メッセージ, 1: マーケティングメッセージ, 2: 価格と特典の説明
  Package? _package;
  bool _isProcessingPurchase = false;
  bool _showPurchaseButtons = false; // 購入ボタンを表示するかどうか
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _purchaseButtonKey = GlobalKey();
  
  final List<String> _messages = [
    '素晴らしい👏\n単語を調べたり、AIに質問したり、リスニング音声を作ったり\nいろいろ触ってみましたね！',
    'でも、実はLingoSavorには\nまだまだ隠された機能があるんです🎁❓',
    '例えば、保存した単語をフラッシュカードで復習できたり📝',
    '保存した単語やAIへの質問をもとに、毎日復習問題を作成してくれたり📚',
    'これらの機能は、これから使っていくうちに自然と気づくと思います😊💞',
  ];
  
  final List<String> _marketingMessages = [
    'ところで、LingoSavorを快適に使ってもらうためにお伝えしておきたいことがあります😊',
    'LingoSavorは、性能の良いAIモデルを使っているため、どうしても多くの広告を表示せざるを得ない状況です',
    'でも、集中して学習したい時は\n広告が邪魔になってしまいますよね😓',
    'そこで、広告が一年間一切表示されないプランをご用意しました！',
  ];
  
  final List<String> _offerMessages = [
    '通常月額980円でご利用いただくと\n年間で11,760円かかります',
    'でも、年額プランなら6,980円で\n約40%オフ、年間で4,780円もお得です🎉',
    'さらに、最初の一週間は無料でお試しいただけます！🎉',
    'しかも！LingoSavorでは英文を登録するのにGEMというアプリ内通貨が必要なのですが',
    '通常7000円分のGEMのところ\nこのページからご登録した人に"だけ"🎉\n💎GEM💎2000円分を追加でプレゼント🎁✨',
    'これだけGEMがあれば、アプリを使ってる時\n不便を感じることは一切ありません😊',
    'もし無料期間中にプランを解除された場合でも\ngemはあなたのものとして残ります😊💎',
    'ぜひ購入してLingoSavorの機能を最大限活用してください💪💖',
  ];
  
  late List<AnimationController> _animationControllers;
  late List<Animation<Offset>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeRevenueCat();
    // 最初のメッセージを表示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNextMessage();
    });
  }
  
  /// RevenueCatの初期化とOfferingsの取得
  Future<void> _initializeRevenueCat() async {
    try {
      // Offeringsを取得
      final offerings = await Purchases.getOfferings();
      
      // 年額プランのパッケージを探す
      Package? annualPackage;
      if (offerings.current != null) {
        final packages = offerings.current!.availablePackages;
        annualPackage = packages.where((p) => 
          p.storeProduct.identifier == 'com.eisukeinoue.lingosavor.adfree.annual'
        ).firstOrNull;
      }
      
      setState(() {
        _package = annualPackage;
      });
    } catch (e) {
      // エラーが発生しても処理を続行
    }
  }

  void _initializeAnimations() {
    final totalMessages = _messages.length + _marketingMessages.length + _offerMessages.length;
    _animationControllers = List.generate(
      totalMessages,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );

    _slideAnimations = _animationControllers.map((controller) {
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
      ));
    }).toList();

    _fadeAnimations = _animationControllers.map((controller) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ));
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _animationControllers) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _showNextMessage() {
    if (_currentPhase == 0) {
      // 初期メッセージフロー
      if (_currentMessageIndex < _messages.length) {
        _animationControllers[_currentMessageIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else {
        _resetChatForMarketingPhase();
      }
    } else if (_currentPhase == 1) {
      // マーケティングメッセージフロー
      if (_currentMessageIndex < _marketingMessages.length) {
        final animationIndex = _messages.length + _currentMessageIndex;
        _animationControllers[animationIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else {
        _resetChatForOfferPhase();
      }
    } else if (_currentPhase == 2) {
      // 価格と特典の説明フロー
      if (_currentMessageIndex < _offerMessages.length) {
        final animationIndex = _messages.length + _marketingMessages.length + _currentMessageIndex;
        _animationControllers[animationIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else {
        // 全部表示済みなら購入ボタンを表示
        setState(() {
          _showPurchaseButtons = true;
        });
        // ボタン表示後に「無料で始める」ボタンの最下部が画面の最下部に来るようにスクロール
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToPurchaseButton();
        });
      }
    }
  }
  
  void _resetChatForMarketingPhase() {
    setState(() {
      _currentPhase = 1;
      _currentMessageIndex = 0;
    });
    
    // アニメーションコントローラーをリセット
    for (var controller in _animationControllers) {
      controller.reset();
    }
    
    // 少し間を置いてからマーケティングメッセージを開始
    Future.delayed(const Duration(milliseconds: 500), () {
      _showNextMessage();
    });
  }
  
  void _resetChatForOfferPhase() {
    setState(() {
      _currentPhase = 2;
      _currentMessageIndex = 0;
    });
    
    // アニメーションコントローラーをリセット
    for (var controller in _animationControllers) {
      controller.reset();
    }
    
    // 少し間を置いてから価格と特典の説明を開始
    Future.delayed(const Duration(milliseconds: 500), () {
      _showNextMessage();
    });
  }

  /// 「無料で始める」ボタンの最下部が画面の最下部に来るようにスクロール
  void _scrollToPurchaseButton() {
    if (!_scrollController.hasClients) return;
    
    final context = _purchaseButtonKey.currentContext;
    if (context == null) return;
    
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // ボタンの位置を取得（グローバル座標）
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    
    // SingleChildScrollViewのRenderBoxを取得
    final scrollViewRenderBox = _scrollController.position.context.storageContext.findRenderObject() as RenderBox?;
    if (scrollViewRenderBox == null) return;
    
    // SingleChildScrollViewの位置を取得（グローバル座標）
    final scrollViewPosition = scrollViewRenderBox.localToGlobal(Offset.zero);
    
    // スクロールビュー内でのボタンの相対位置を計算
    final buttonTopRelativeToScrollView = buttonPosition.dy - scrollViewPosition.dy;
    final buttonHeight = renderBox.size.height;
    final buttonBottomRelativeToScrollView = buttonTopRelativeToScrollView + buttonHeight;
    
    // スクロールビューの高さを取得
    final scrollViewHeight = _scrollController.position.viewportDimension;
    
    // 現在のスクロール位置を取得
    final currentScrollOffset = _scrollController.offset;
    
    // ボタンの最下部が画面の最下部に来るようにスクロール位置を計算
    // buttonBottomRelativeToScrollViewは現在のスクロール位置を考慮した値なので、
    // ボタンの最下部が画面の最下部に来るには、currentScrollOffset + buttonBottomRelativeToScrollView = scrollViewHeight
    // つまり、targetScrollOffset = buttonBottomRelativeToScrollView - scrollViewHeight + currentScrollOffset
    final targetScrollPosition = currentScrollOffset + buttonBottomRelativeToScrollView - scrollViewHeight;
    
    if (targetScrollPosition >= 0 && targetScrollPosition <= _scrollController.position.maxScrollExtent) {
      _scrollController.animateTo(
        targetScrollPosition,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  /// RevenueCatで購入処理を実行
  Future<void> _purchasePackage() async {
    if (_isProcessingPurchase || _package == null) return;
    
    try {
      setState(() {
        _isProcessingPurchase = true;
      });
      
      // 購入前にFirebaseユーザーIDでRevenueCatにログインしているか確認
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await Purchases.logIn(user.uid);
      }
      
      // 通常価格で購入
      await Purchases.purchasePackage(_package!);
      
      // 少し待ってから最新のCustomerInfoを取得
      await Future.delayed(const Duration(milliseconds: 500));
      final latestCustomerInfo = await Purchases.getCustomerInfo();
      
      // 購入後の権限を確認
      await _handlePurchaseSuccess(latestCustomerInfo);
      
    } on PlatformException catch (e) {
      _handlePurchaseError(e);
    } catch (e) {
      _showErrorDialog('購入処理中にエラーが発生しました: $e');
    } finally {
      setState(() {
        _isProcessingPurchase = false;
      });
    }
  }

  /// 購入成功後の処理
  Future<void> _handlePurchaseSuccess(CustomerInfo customerInfo) async {
    final activeEntitlements = customerInfo.entitlements.active;
    
    if (activeEntitlements.isNotEmpty) {
      // 購入成功
      // gemを5000追加
      await _addGemsToUser(5000);
      
      // チュートリアル完了処理を実行してページを閉じる
      await _completeTutorial(purchased: true);
    } else {
      _showErrorDialog('購入が完了しましたが、権限の確認に失敗しました。しばらく待ってから再度お試しください。');
    }
  }

  /// gemをユーザーに追加
  Future<void> _addGemsToUser(int gems) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // add-gems Cloud Functionを呼び出し
      final callable = FirebaseFunctions.instance.httpsCallable('addGems');
      await callable.call({
        'gem': gems,
        'user_id': user.uid,
        'isAd': false,
      });
    } catch (e) {
      print('Gem追加エラー: $e');
      // エラーが発生しても処理を続行（購入自体は成功しているため）
    }
  }

  /// RevenueCat購入エラーを処理する
  void _handlePurchaseError(PlatformException error) {
    String errorMessage = '購入に失敗しました。';
    
    switch (error.code) {
      case '1': // User cancelled
        errorMessage = '購入がキャンセルされました。';
        break;
      case '2': // Store problem
        errorMessage = 'App Storeに接続できませんでした。';
        break;
      case '3': // Purchase not allowed
        errorMessage = '購入が許可されていません。設定を確認してください。';
        break;
      case '4': // Purchase invalid
        errorMessage = '無効な購入です。';
        break;
      case '5': // Product not available
        errorMessage = 'この商品は現在利用できません。';
        break;
      case '6': // Purchase already owned
        errorMessage = 'この商品は既に購入済みです。';
        break;
      case '8': // Network error
        errorMessage = 'ネットワークエラーが発生しました。';
        break;
      default:
        errorMessage = '購入処理中にエラーが発生しました。(${error.code})';
    }
    
    // ユーザーがキャンセルした場合はダイアログを表示しない
    if (error.code != '1') {
      _showErrorDialog(errorMessage);
    }
  }

  /// エラーダイアログを表示
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // チュートリアル完了処理
  Future<void> _completeTutorial({bool purchased = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('second_tutorial_shown', true);
    
    if (mounted) {
      // 購入完了の場合はページを閉じる
      Navigator.of(context).pop();
    }
  }

  /// チュートリアル終了確認ダイアログを表示
  void _showExitConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('本当によろしいですか？', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'お得な年額プランをご利用ください！',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 16),
              Text(
                '✨ 年額プランのメリット',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '• 通常月額980円 × 12ヶ月 = '),
                    const TextSpan(
                      text: '¥11,760',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '• 年額プランなら '),
                    const TextSpan(
                      text: '¥6,980',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '（約40%オフ）'),
                  ],
                ),
              ),
              Text('• 一週間無料でお試し可能'),
              SizedBox(height: 16),
              Text(
                '⚠️ このページを離れると...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 8),
              Text('• 広告が表示され続けます'),
              Text('• 2000円分のGEMが二度と無料で貰えなくなります‼️‼️', style: TextStyle(fontWeight: FontWeight.bold),),
              SizedBox(height: 16),
              Text(
                '今すぐ無料で始めて、LingoSavorを最大限に活用しましょう！💪✨',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text(
              '購入する',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // ダイアログを閉じる
              await _completeTutorial();
            },
            child: const Text(
              'それでも終了する',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String message, int index) {
    // 価格を太字にするためのTextSpanを作成
    List<TextSpan> spans = [];
    String remainingText = message;
    
    // 価格パターンを検出して太字にする（11,760円と6,980円のみ）
    final pricePatterns = [
      '11,760円',
      '6,980円',
    ];
    
    // すべての価格パターンを検出して位置を記録
    List<({int start, int end, String pattern})> matches = [];
    for (var pattern in pricePatterns) {
      int startIndex = 0;
      while (true) {
        final index = remainingText.indexOf(pattern, startIndex);
        if (index == -1) break;
        matches.add((start: index, end: index + pattern.length, pattern: pattern));
        startIndex = index + 1;
      }
    }
    
    // 開始位置でソート
    matches.sort((a, b) => a.start.compareTo(b.start));
    
    // TextSpanを作成
    int currentIndex = 0;
    for (var match in matches) {
      // マッチより前のテキストを追加
      if (currentIndex < match.start) {
        spans.add(TextSpan(
          text: remainingText.substring(currentIndex, match.start),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ));
      }
      
      // 価格を太字で追加（より太く）
      spans.add(TextSpan(
        text: match.pattern,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black,
          fontWeight: FontWeight.w900,
        ),
      ));
      
      currentIndex = match.end;
    }
    
    // 残りのテキストを追加
    if (currentIndex < remainingText.length) {
      spans.add(TextSpan(
        text: remainingText.substring(currentIndex),
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black,
          fontWeight: FontWeight.w500,
        ),
      ));
    }
    
    // 価格が見つからなかった場合は元のメッセージを使用
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: message,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black,
          fontWeight: FontWeight.w500,
        ),
      ));
    }
    
    return SlideTransition(
      position: _slideAnimations[index],
      child: FadeTransition(
        opacity: _fadeAnimations[index],
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text.rich(
              TextSpan(children: spans),
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.lerp(Colors.white, Theme.of(context).colorScheme.primary, 0.4),
      body: GestureDetector(
        onTap: _showPurchaseButtons ? null : _showNextMessage,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Column(
            children: [
              // メッセージエリア
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...List.generate(_currentMessageIndex, (index) {
                        if (_currentPhase == 0) {
                          // 初期メッセージ
                          return _buildMessageBubble(_messages[index], index);
                        } else if (_currentPhase == 1) {
                          // マーケティングメッセージ
                          return _buildMessageBubble(_marketingMessages[index], _messages.length + index);
                        } else {
                          // 価格と特典の説明
                          return _buildMessageBubble(_offerMessages[index], _messages.length + _marketingMessages.length + index);
                        }
                      }),
                      // 購入ボタンと終了ボタンを表示
                      if (_showPurchaseButtons) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          key: _purchaseButtonKey,
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isProcessingPurchase || _package == null ? null : _purchasePackage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isProcessingPurchase
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('処理中...'),
                                    ],
                                  )
                                : const Text(
                                    '無料で始める',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _showExitConfirmationDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[600],
                              side: BorderSide(color: Colors.grey[400]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'チュートリアルを終了する',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
