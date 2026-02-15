import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../pages/conversation_page.dart';
import '../../pages/word_detail_page.dart';
import 'selection_bottom_sheet.dart';

class TokensContent extends StatefulWidget {
  final Map<String, dynamic> savorResult;
  final String documentId;
  final String? listId;
  final bool isSelectionMode; // true: 範囲選択モード, false: 単語詳細モード
  final VoidCallback? onReturnFromWordDetail; // word_detail_pageから戻ってきた時のコールバック
  final VoidCallback? onReturnFromConversation; // conversation_pageから戻ってきた時のコールバック

  const TokensContent({
    super.key,
    required this.savorResult,
    required this.documentId,
    this.listId,
    required this.isSelectionMode,
    this.onReturnFromWordDetail,
    this.onReturnFromConversation,
  });

  @override
  State<TokensContent> createState() => _TokensContentState();
}

class _TokensContentState extends State<TokensContent> {
  // 範囲選択用の状態変数
  int? _selectionStartIndex;
  int? _selectionEndIndex;
  bool _isSelecting = false;
  
  // 単語詳細モード用のローディング状態
  bool _isLoading = false;
  OverlayEntry? _overlayEntry;
  
  // 全トークンのリスト
  List<String> _allTokens = [];
  List<Map<String, dynamic>> _paragraphsWithWords = [];
  
  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // ユーザープラン情報
  String _userPlan = 'free';
  
  // チュートリアル用
  final GlobalKey _firstParagraphKey = GlobalKey();

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
  void initState() {
    super.initState();
    _processParagraphs();
    _loadUserPlan();
    
    // チュートリアルの開始（単語詳細モードの場合のみ）
    if (!widget.isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowTutorial();
      });
    }
  }
  
  // チュートリアルを表示するかチェック
  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial = prefs.getBool('tokens_content_tutorial_shown') ?? false;
    
    if (!hasShownTutorial && mounted) {
      // チュートリアルを表示
      ShowCaseWidget.of(context).startShowCase([_firstParagraphKey]);
      // フラグを保存
      await prefs.setBool('tokens_content_tutorial_shown', true);
    }
  }

  // ユーザープラン情報を取得
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
          setState(() {
            _userPlan = data?['plan'] ?? 'free';
          });
        }
      }
    } catch (e) {
      // エラーが発生した場合はデフォルトのfreeプランを維持
      print('Error loading user plan: $e');
    }
  }

  @override
  void didUpdateWidget(TokensContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // モードが変更された場合、選択状態をリセット
    if (oldWidget.isSelectionMode != widget.isSelectionMode) {
      setState(() {
        _selectionStartIndex = null;
        _selectionEndIndex = null;
        _isSelecting = false;
      });
    }
  }

  // paragraphs_with_wordsを処理
  void _processParagraphs() {
    final paragraphsWithWords = (widget.savorResult['paragraphs_with_words'] as List?)?.map((p) => p as Map<String, dynamic>).toList() ?? [];
    
    if (paragraphsWithWords.isEmpty) {
      return;
    }
    
    final allTokens = <String>[];
    
    for (final paragraphData in paragraphsWithWords) {
      final words = (paragraphData['words'] as List?)?.map((w) => w.toString()).toList() ?? [];
      allTokens.addAll(words);
    }

    setState(() {
      _paragraphsWithWords = paragraphsWithWords;
      _allTokens = allTokens;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_paragraphsWithWords.isEmpty) {
      return const Center(child: Text('段落データがありません'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      itemCount: _paragraphsWithWords.length,
      itemBuilder: (context, paragraphIndex) {
        final paragraphData = _paragraphsWithWords[paragraphIndex];
        final paragraph = paragraphData['paragraph'] as String? ?? '';
        final words = (paragraphData['words'] as List?)?.map((w) => w.toString()).toList() ?? [];
        
        if (words.isEmpty) {
          return const SizedBox.shrink();
        }

        // この段落の開始トークンインデックスを計算
        int currentTokenIndex = 0;
        for (int i = 0; i < paragraphIndex; i++) {
          final prevWords = (_paragraphsWithWords[i]['words'] as List?)?.length ?? 0;
          currentTokenIndex += prevWords;
        }

        final List<InlineSpan> spans = [];
        
        for (int wordIndex = 0; wordIndex < words.length; wordIndex++) {
          final word = words[wordIndex];
          final absoluteTokenIndex = currentTokenIndex + wordIndex;
          
          // 単語の前にスペースを追加（最初の単語以外、かつ句読点でない場合）
          if (wordIndex > 0 && !_isPunctuation(word)) {
            spans.add(const TextSpan(text: ' '));
          }
          
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _buildSelectableToken(word, absoluteTokenIndex, paragraph),
            ),
          );
        }

        final paragraphWidget = Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 20,
                color: Colors.black87,
                height: 1.6,
                fontWeight: FontWeight.w400,
                fontFamily: 'Georgia',
              ),
              children: spans,
            ),
          ),
        );

        // 最初の段落にShowcaseを追加（単語詳細モードの場合のみ）
        if (paragraphIndex == 0 && !widget.isSelectionMode) {
          return Showcase(
            key: _firstParagraphKey,
            title: 'わからない単語をタップ',
            description: '単語の意味だけでなく例文やニュアンス、類義語、派生語、語源を学べます💞',
            targetPadding: const EdgeInsets.all(8),
            child: paragraphWidget,
          );
        }
        
        return paragraphWidget;
      },
    );
  }

  // 句読点かどうかを判定するヘルパーメソッド
  bool _isPunctuation(String token) {
    final punctuationRegex = RegExp(r'^[.,!?;:"()[\]{}]$');
    return punctuationRegex.hasMatch(token);
  }

  // 選択可能な単語ウィジェットを構築
  Widget _buildSelectableToken(String token, int absoluteTokenIndex, String paragraph) {
    bool isSelected = false;
    Color backgroundColor = Colors.transparent;
    Color textColor = Colors.black87;

    // 範囲選択モードの場合の選択範囲判定
    if (widget.isSelectionMode) {
      if (_selectionStartIndex != null && _selectionEndIndex != null) {
        final start = _selectionStartIndex!;
        final end = _selectionEndIndex!;
        final minIndex = start < end ? start : end;
        final maxIndex = start < end ? end : start;
        
        if (absoluteTokenIndex >= minIndex && absoluteTokenIndex <= maxIndex) {
          isSelected = true;
          backgroundColor = Colors.blue.shade200;
          textColor = Colors.white;
        }
      } else if (_selectionStartIndex == absoluteTokenIndex) {
        isSelected = true;
        backgroundColor = Colors.blue.shade300;
        textColor = Colors.white;
      }
    }

    return GestureDetector(
      onTap: () => _handleTokenTap(absoluteTokenIndex, token, paragraph),
      child: Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: backgroundColor,
        ),
        child: Text(
          token,
           style: TextStyle(
             fontSize: 20,
             color: textColor,
             fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
             height: 1.6,
             fontFamily: 'Georgia',
             decoration: widget.isSelectionMode ? TextDecoration.none : TextDecoration.underline,
           ),
        ),
      ),
    );
  }

  // 単語タップ時の処理
  void _handleTokenTap(int absoluteTokenIndex, String token, String paragraph) {
    if (widget.isSelectionMode) {
      // 範囲選択モード
      _handleSelectionMode(absoluteTokenIndex);
    } else {
      // 単語詳細モード
      _handleWordDetailMode(token, paragraph);
    }
  }

  // 範囲選択モードの処理
  void _handleSelectionMode(int index) {
    setState(() {
      if (!_isSelecting) {
        // 選択開始
        _selectionStartIndex = index;
        _isSelecting = true;
        _selectionEndIndex = null;
      } else {
        // 選択終了
        _selectionEndIndex = index;
        _isSelecting = false;
        
        // 選択完了時にボトムシートを表示
        _showSelectionBottomSheet();
      }
    });
  }

  // 単語詳細モードの処理
  Future<void> _handleWordDetailMode(String word, String paragraph) async {
    if (_isLoading) return;
    
    _isLoading = true;
    _showLoadingOverlay();

    try {
      // 認証状態の確認
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        throw Exception('ユーザーが認証されていません');
      }

      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('generateMeanings');
      
      final result = await callable.call({
        'word': word,
        'sentence': paragraph,
      });
      if (!_isLoading) {
        return;
      }
      
      // 安全な型キャスト
      final dynamic rawData = result.data;
      final responseData = _convertToMap(rawData);
      
      if (responseData['success'] == true && responseData['data'] != null) {
        if (context.mounted) {
          // ネストしたデータも安全に変換
          final analysisData = _convertToMap(responseData['data']);
          _showDetailedWordBottomSheet(context, analysisData, paragraph);
        }
      } else {
        if (context.mounted) {
          _showMessage('❌ 単語情報の取得に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        String errorMessage = '❌ 単語情報の取得に失敗しました';
        switch (e.code) {
          case 'unauthenticated':
            errorMessage = '❌ 認証が必要です。ログインしてください。';
            break;
          case 'invalid-argument':
            errorMessage = '❌ 無効なパラメータです。';
            break;
          case 'internal':
            errorMessage = '❌ サーバーエラーが発生しました。';
            break;
          default:
            errorMessage = '❌ エラーが発生しました: ${e.message}';
            break;
        }
        _showMessage(errorMessage);
      }
    } catch (e) {
      if (context.mounted) {
        _showMessage('❌ 単語情報の取得でエラーが発生しました: $e');
      }
    } finally {
      _isLoading = false;
      _hideLoadingOverlay();
    }
  }

  // 選択範囲のボトムシート表示
  void _showSelectionBottomSheet() {
    if (_selectionStartIndex == null || _selectionEndIndex == null) return;
    
    final start = _selectionStartIndex!;
    final end = _selectionEndIndex!;
    final minIndex = start < end ? start : end;
    final maxIndex = start < end ? end : start;
    
    final selectedTokens = _allTokens.sublist(minIndex, maxIndex + 1);
    final selectedText = selectedTokens.join(' ');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SelectionBottomSheet(
          selectedText: selectedText,
          onQuickAction: _handleQuickAction,
          onCustomQuestion: _handleCustomQuestion,
          userPlan: _userPlan,
        );
      },
    );
  }

  // 単語詳細のボトムシート表示
  Future<void> _showDetailedWordBottomSheet(BuildContext context, Map<String, dynamic> responseData, String? originalSentence) async {
    final String dictionaryId = responseData['dictionary_id'] ?? '';
    final Map<String, dynamic> analysisData = {
      'original_word': responseData['original_word'],
      'base_word': responseData['base_word'],
      'word_form': responseData['word_form'],
      'part_of_speech': responseData['part_of_speech'],
      'context_role': responseData['context_role'],
      'examples': responseData['examples'], // examples フィールドを追加
    };
    
    print('🔍 tokens_content: responseData examples: ${responseData['examples']}');
    print('🔍 tokens_content: analysisData examples: ${analysisData['examples']}');

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WordDetailPage(
          dictionaryId: dictionaryId,
          analysisData: analysisData,
          listId: widget.listId,
          originalSentence: originalSentence,
          documentId: widget.documentId,
        ),
      ),
    );
    
    // word_detail_pageから戻ってきた時の処理
    if (result == true && widget.onReturnFromWordDetail != null) {
      widget.onReturnFromWordDetail!();
    }
  }

  // ローディングオーバーレイの表示
  void _showLoadingOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  '単語を解析しています...\nしばらくお待ちください',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    _isLoading = false;
                    _hideLoadingOverlay();
                  },
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ローディングオーバーレイの非表示
  void _hideLoadingOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideLoadingOverlay();
    super.dispose();
  }

  // クイックアクション処理
  void _handleQuickAction(String selectedText, String actionType, String aiModel) {
    Navigator.of(context).pop();
    
    if (actionType == 'meaning') {
      // 単語数をチェック
      final words = selectedText.trim().split(RegExp(r'\s+'));
      if (words.length <= 10) {
        // 10単語以内の場合、generate-meaningsを呼び出してword_detail_pageを表示
        _handleMeaningAction(selectedText);
        return;
      }
    }
    
    String question = '';
    switch (actionType) {
      case 'grammar':
        question = '「$selectedText」の文法構造を詳しく説明してください。';
        break;
      case 'meaning':
        question = '「$selectedText」の意味を詳しく教えてください。';
        break;
      case 'context_meaning':
        question = 'この文章において「$selectedText」はどのような意味で使われていますか？文脈に基づいて説明してください。';
        break;
    }
    
    _createConversationAndNavigate(question, aiModel);
  }

  // 意味を知りたいアクションの処理（10単語以内の場合）
  Future<void> _handleMeaningAction(String selectedText) async {
    if (_isLoading) return;
    
    _isLoading = true;
    _showLoadingOverlay();

    try {
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('generateMeanings');
      
      final result = await callable.call({
        'word': selectedText,
        'sentence': '', // 文脈がない場合は空文字
      });
      if (!_isLoading) {
        return;
      }
      
      // 安全な型キャスト
      final dynamic rawData = result.data;
      final responseData = _convertToMap(rawData);
      
      if (responseData['success'] == true && responseData['data'] != null) {
        if (context.mounted) {
          // ネストしたデータも安全に変換
          final analysisData = _convertToMap(responseData['data']);
          _showDetailedWordBottomSheet(context, analysisData, null);
        }
      } else {
        if (context.mounted) {
          _showMessage('❌ 単語情報の取得に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        String errorMessage = '❌ 単語情報の取得に失敗しました';
        switch (e.code) {
          case 'unauthenticated':
            errorMessage = '❌ 認証が必要です。ログインしてください。';
            break;
          case 'invalid-argument':
            errorMessage = '❌ 無効なパラメータです。';
            break;
          case 'internal':
            errorMessage = '❌ サーバーエラーが発生しました。';
            break;
          default:
            errorMessage = '❌ エラーが発生しました: ${e.message}';
            break;
        }
        _showMessage(errorMessage);
      }
    } catch (e) {
      if (context.mounted) {
        _showMessage('❌ 単語情報の取得でエラーが発生しました: $e');
      }
    } finally {
      _isLoading = false;
      _hideLoadingOverlay();
    }
  }

  // カスタム質問処理
  void _handleCustomQuestion(String selectedText, String question, String aiModel) {
    Navigator.of(context).pop();
    final fullQuestion = '「$selectedText」について：$question';
    _createConversationAndNavigate(fullQuestion, aiModel);
  }

  // 新しい会話を作成してページ遷移
  Future<void> _createConversationAndNavigate(String question, String aiModel) async {
    try {
      _showMessage('📝 新しい会話を作成中...', isSuccess: true);
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('❌ ログインが必要です');
        return;
      }

      final roomRef = await FirebaseFirestore.instance.collection('user_rooms').add({
        'title': question.length > 50 ? '${question.substring(0, 50)}...' : question,
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'document_id': widget.documentId,
        'model': aiModel,
      });

      await FirebaseFirestore.instance.collection('messages').add({
        'role': 'user',
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'content': question,
        'room_id': roomRef.id,
      });

      // 即座に会話ページに遷移
      _navigateToConversation(roomRef.id, question);
      
      // generate-responseは非同期で実行（完了を待たない）
      _callGenerateResponse(roomRef.id);

    } catch (e) {
      _showMessage('❌ 会話の作成でエラーが発生しました: $e');
    }
  }

  // Firebase Functionsのgenerate-responseを呼び出し
  Future<void> _callGenerateResponse(String roomId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('generateResponse');
      
      final result = await callable.call({
        'room_id': roomId,
        'transcription': '',
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

  // 会話ページに遷移
  Future<void> _navigateToConversation(String roomId, String title) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConversationPage(
          roomId: roomId,
          title: title,
        ),
      ),
    );
    
    // conversation_pageから直接戻ってきた時の処理
    if (result == true && widget.onReturnFromConversation != null) {
      widget.onReturnFromConversation!();
    }
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
} 