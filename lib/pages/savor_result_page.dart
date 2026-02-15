import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/savor_result_tabs/summary_tab.dart';
import '../widgets/savor_result_tabs/translation_tab.dart';
import '../widgets/savor_result_tabs/tokens_content.dart';
import '../widgets/savor_result_tabs/published_words_tab.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/savor_result_tabs/rooms_tab.dart';
import '../widgets/saved_words_tab.dart';
import 'speech_to_text_page.dart';
import 'subscription_page.dart';
import 'reading_mode_page.dart'; 
import 'package:cloud_functions/cloud_functions.dart';
import '../widgets/global_loading_manager.dart';
import '../services/admob_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'second_tutorial_page.dart';

class SavorResultPage extends StatefulWidget {
  final String documentId;
  final String title;
  final Map<String, dynamic> savorResult;

  const SavorResultPage({
    super.key,
    required this.documentId,
    required this.title,
    required this.savorResult,
  });

  @override
  State<SavorResultPage> createState() => _SavorResultPageState();
}

class _SavorResultPageState extends State<SavorResultPage> {
  String? _listId;
  bool _isBasicTokenMode = false; // false: 単語詳細モード, true: 範囲選択モード
  final GlobalLoadingManager _loadingManager = GlobalLoadingManager();
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  
  // チュートリアル用のGlobalKey
  final GlobalKey _summaryTabKey = GlobalKey();
  final GlobalKey _translationTabKey = GlobalKey();
  final GlobalKey _publishedWordsTabKey = GlobalKey();
  final GlobalKey _bookmarkTabKey = GlobalKey();
  final GlobalKey _selectionButtonKey = GlobalKey();
  final GlobalKey _roomTabKey = GlobalKey();
  final GlobalKey _audioTabKey = GlobalKey();
  
  // ShowCaseWidget内のBuildContextを保存
  BuildContext? _showcaseContext;

  @override
  void initState() {
    super.initState();
    _loadListId();
    _initializeBannerAd();
  }

  void _initializeBannerAd() async {
    _bannerAd = await AdMobService.createBannerAd(
      onAdLoaded: () {
        setState(() {
          _isBannerAdReady = true;
        });
      },
      onAdFailedToLoad: (error) {
        setState(() {
          _isBannerAdReady = false;
        });
      },
    );
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadListId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // user_wordlistsコレクションから該当するdocument_idのlist_idを取得（存在する場合のみ）
      final querySnapshot = await FirebaseFirestore.instance
          .collection('user_wordlists')
          .where('document_id', isEqualTo: widget.documentId)
          .where('user_id', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          _listId = querySnapshot.docs.first.id;
        });
      }
      // wordlistが存在しない場合は_listIdをnullのままにする（遅延作成）
    } catch (e) {
      // エラーをログに記録しつつ、処理を継続
    }
  }
  
  // word_detail_pageから戻ってきた時のチュートリアル表示
  Future<void> _showHeaderTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final wordDetailVisited = prefs.getBool('word_detail_visited') ?? false;
    final headerTutorialShown = prefs.getBool('header_tutorial_shown') ?? false;
    
    // word_detail_pageを訪問済み、かつヘッダーチュートリアル未表示の場合
    if (wordDetailVisited && !headerTutorialShown && mounted && _showcaseContext != null) {
      // WidgetsBindingを使用して次のフレームで実行（コンテキストが確実に利用可能になってから）
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && _showcaseContext != null) {
          try {
            ShowCaseWidget.of(_showcaseContext!).startShowCase([
              _summaryTabKey, 
              _translationTabKey, 
              _bookmarkTabKey, 
              _selectionButtonKey
            ]);
            await prefs.setBool('header_tutorial_shown', true);
          } catch (e) {
            print('チュートリアル表示エラー: $e');
          }
        }
      });
    }
  }
  
  // conversation_pageから戻ってきた時のチュートリアル表示
  Future<void> _showConversationTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final conversationTutorialShown = prefs.getBool('conversation_tutorial_shown') ?? false;
    
    // チュートリアル未表示の場合のみ表示
    if (!conversationTutorialShown && mounted && _showcaseContext != null) {
      // WidgetsBindingを使用して次のフレームで実行
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && _showcaseContext != null) {
          try {
            ShowCaseWidget.of(_showcaseContext!).startShowCase([_roomTabKey, _audioTabKey]);
            await prefs.setBool('conversation_tutorial_shown', true);
          } catch (e) {
            print('チュートリアル表示エラー: $e');
          }
        }
      });
    }
  }
  
  // ShowCaseWidget完了後に呼ばれる
  Future<void> _onShowCaseComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final conversationTutorialShown = prefs.getBool('conversation_tutorial_shown') ?? false;
    final secondTutorialShown = prefs.getBool('second_tutorial_shown') ?? false;
    
    // 質問→リスニングのチュートリアルが完了していて、かつ第2チュートリアルが未表示の場合
    if (conversationTutorialShown && !secondTutorialShown && mounted) {
      // 少し遅延を入れてからチュートリアルページを表示
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SecondTutorialPage(),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      onFinish: () {
        // ShowCaseが完了したら第2チュートリアルを表示
        _onShowCaseComplete();
      },
      builder: (context) {
        // ShowCaseWidget内のコンテキストを保存
        _showcaseContext = context;
        return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.black),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 48, // ヘッダーを短くする
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black),
              onSelected: (value) {
                if (value == 'reading_mode') {
                  _navigateToReadingMode();
                }
              },
              itemBuilder: (BuildContext context) => const [
                PopupMenuItem<String>(
                  value: 'reading_mode',
                  child: Text('Reading Mode'),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            // メインコンテンツ
            Column(
              children: [
                // タブバーに音声タブを追加
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // 左側の「選択」ボタン
                      Showcase(
                        key: _selectionButtonKey,
                        title: 'タップしてAIに質問しよう！',
                        description: 'タップすると範囲選択モードに切り替わり、熟語やイディオムの意味を調べられたり、文法がわからない文章をAIに質問できたりします！',
                        targetPadding: const EdgeInsets.all(8),
                        child: GestureDetector(
                          onTap: () => setState(() => _isBasicTokenMode = !_isBasicTokenMode),
                          child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: _isBasicTokenMode 
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  '選択',
                                  style: TextStyle(
                                    color: _isBasicTokenMode
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ),
                      const SizedBox(width: 16),
                      // 右側のタブ
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Showcase(
                              key: _summaryTabKey,
                              title: '概要・文化的背景',
                              description: '全体の要約や、理解に役立つ文化的背景を確認できます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildTabItem(Icons.summarize_outlined, '概要', () => _navigateToSummary()),
                            ),
                            Showcase(
                              key: _translationTabKey,
                              title: '翻訳',
                              description: '一文ごとに翻訳を確認できます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildTabItem(Icons.translate_outlined, '翻訳', () => _navigateToTranslation()),
                            ),
                            Showcase(
                              key: _roomTabKey,
                              title: '質問',
                              description: 'AIへの質問はここから見返せます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildTabItem(Icons.chat_bubble_outline, '質問', () => _navigateToRoom()),
                            ),
                            Showcase(
                              key: _publishedWordsTabKey,
                              title: '教材',
                              description: '市販の単語帳に収録されている単語を確認できます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildTabItem(Icons.menu_book_outlined, '教材', () => _navigateToPublishedWords()),
                            ),
                            Showcase(
                              key: _bookmarkTabKey,
                              title: '保存',
                              description: '保存した単語を確認できます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildTabItem(Icons.bookmark_outline, '保存', () => _navigateToBookmark()),
                            ),
                            Showcase(
                              key: _audioTabKey,
                              title: 'リスニング音源を作成',
                              description: '文章を音声化して、リピーティングやシャドーイングなどのリスニング練習ができます',
                              targetPadding: const EdgeInsets.all(8),
                              child: _buildAudioTab(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // バナー広告
                if (_isBannerAdReady && _bannerAd != null)
                  Container(
                    width: _bannerAd!.size.width.toDouble(),
                    height: 100,
                    alignment: Alignment.center,
                    child: AdWidget(ad: _bannerAd!),
                  ),
                // タブコンテンツ
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TokensContent(
                      savorResult: widget.savorResult,
                      documentId: widget.documentId,
                      listId: _listId,
                      isSelectionMode: _isBasicTokenMode,
                      onReturnFromWordDetail: _showHeaderTutorial,
                      onReturnFromConversation: _showConversationTutorial,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      },
    );
  }

  Widget _buildTabItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 25,
              color: Colors.grey,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTab() {
    return GestureDetector(
      onTap: () async {
        await _handleAudioButtonTap(); // 新しい処理に変更
      },
      child: Container(
        height: 48,
        width: 48,
        
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.volume_up,
          color: Colors.white,
          size: 28,
        ),
        
      ),
    );
  }

  // 新しい音声ボタンタップ処理
  Future<void> _handleAudioButtonTap() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインが必要です')),
        );
        return;
      }

      // user_audiosコレクションから既存の音声データを検索
      final audioSnapshot = await FirebaseFirestore.instance
          .collection('user_audios')
          .where('user_id', isEqualTo: user.uid)
          .where('document_id', isEqualTo: widget.documentId)
          .limit(1)
          .get();

      if (audioSnapshot.docs.isNotEmpty) {
        // 音声データが存在する場合、SpeechToTextPageに遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SpeechToTextPage(documentId: widget.documentId),
          ),
        );
      } else {
        // 音声データが存在しない場合、生成確認ダイアログを表示
        _showAudioGenerationDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  // 音声生成確認ダイアログ
  void _showAudioGenerationDialog() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインが必要です')),
        );
        return;
      }

      // ユーザーのプラン情報を取得
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final userData = userDoc.data();
      final userPlan = userData?['plan'] ?? 'free';

      if (userPlan == 'free') {
        // freeプランの場合、gem必要量を計算
        await _showAudioGenerationWithGemDialog(user.uid, userData?['gems'] ?? 0);
      } else {
        // プレミアムプランの場合、従来のダイアログを表示
        _showStandardAudioGenerationDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  // プレミアムプラン用の従来のダイアログ
  void _showStandardAudioGenerationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('リスニング音声を作成'),
          content: const Text('この文章から、タイムスタンプのついたリスニング音声とオーバーラッピング用の音声を作成できます。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // ダイアログを閉じる
              },
              child: const Text('いいえ'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // ダイアログを閉じる
                _convertToAudio(); // 音声生成処理を実行
              },
              child: const Text('はい'),
            ),
          ],
        );
      },
    );
  }

  // freeプラン用のgem消費確認ダイアログ
  Future<void> _showAudioGenerationWithGemDialog(String userId, int currentGems) async {
    try {
      // ドキュメントの文字起こしを取得してgem必要量を計算
      final docSnapshot = await FirebaseFirestore.instance
          .collection('user_documents')
          .doc(widget.documentId)
          .get();
      
      final docData = docSnapshot.data();
      final transcription = docData?['transcription'] ?? '';
      
      if (transcription.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文字起こしが見つかりません。先に文字起こしを実行してください。')),
        );
        return;
      }

      // gem必要量を計算（transcription_edit_page.dartと同じ方法）
      final wordCount = transcription.trim().split(RegExp(r'\s+')).length;
      final requiredGems = (wordCount / 10).ceil();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.volume_up, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text('リスニング音声を作成'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('この文章から、タイムスタンプのついたリスニング音声とオーバーラッピング用の音声を作成できます。'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💡 ProプランにアップグレードすればGemを消費せずに音声化できます！',
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SubscriptionPage(),
                            ),
                          );
                        },
                        child: const Text(
                          'プランをアップグレード →',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('必要Gem:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text('$requiredGems', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('現在のGem:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text('$currentGems', style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: currentGems >= requiredGems ? Colors.green : Colors.red,
                          )),
                        ],
                      ),
                    ],
                  ),
                ),

              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: currentGems >= requiredGems ? () {
                  Navigator.of(context).pop();
                  _convertToAudio();
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('Gem消費 ($requiredGems)'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  Future<void> _convertToAudio() async {
    try {
      // ローディング開始
      _loadingManager.showLoading(message: '音声化中...');

      // Firebase Functions の textToSpeech を onCall で呼び出し
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('textToSpeech');
      
      final result = await callable.call({
        'documentId': widget.documentId,
      });

      if (result.data['success'] == true) {
        // 成功した場合、SpeechToTextPageに遷移
        if (mounted) {
          _loadingManager.hideLoading();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SpeechToTextPage(documentId: widget.documentId),
            ),
          );
        }
      } else {
        throw Exception('音声化に失敗しました: ${result.data['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      // エラーハンドリング
      if (mounted) {
        _loadingManager.hideLoading();
        
        String errorMessage = '音声化中にエラーが発生しました';
        
        // エラーメッセージから特定のエラーを判定
        if (e.toString().contains('Transcription is too long')) {
          errorMessage = 'テキストが長すぎます（5000文字以内にしてください）';
        } else if (e.toString().contains('Transcription not found')) {
          errorMessage = '文字起こしデータが見つかりません。先に文字起こしを行ってください。';
        } else {
          errorMessage = '音声化中にエラーが発生しました: $e';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  void _navigateToSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('概要・文化的背景', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.black),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 48,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SummaryTab(savorResult: widget.savorResult),
          ),
        ),
      ),
    );
  }

  void _navigateToTranslation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('翻訳', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.black),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 48,
          ),
          body: TranslationTab(
            savorResult: widget.savorResult,
            documentId: widget.documentId,
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToRoom() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('質問', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.black),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 48,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: RoomsTab(
              documentId: widget.documentId,
              onReturnFromConversation: (_) => _showConversationTutorial(),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToPublishedWords() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('教材に収録されている単語', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.black),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 48,
          ),
          body: PublishedWordsTab(savorResult: widget.savorResult),
        ),
      ),
    );
  }

  void _navigateToBookmark() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインが必要です')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('保存した単語', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.black),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 48,
          ),
          body: Padding(
            padding: const EdgeInsets.all(0),
            child: SavedWordsTab(
              user: user,
              documentId: widget.documentId,
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToReadingMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReadingModePage(
          documentId: widget.documentId,
          title: widget.title,
        ),
      ),
    );
  }
}

// RoomsTabはlib/widgets/savor_result_tabs/rooms_tab.dartへ切り出し済み
