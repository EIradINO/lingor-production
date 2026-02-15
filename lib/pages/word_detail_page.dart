import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'save_word_page.dart';
import '../widgets/edit_meanings_bottom_sheet.dart';

class WordDetailPage extends StatefulWidget {
  final String? dictionaryId;
  final Map<String, dynamic>? analysisData;
  final String? listId;
  final String? originalSentence;
  final String? documentId;

  const WordDetailPage({
    super.key,
    this.dictionaryId,
    this.analysisData,
    this.listId,
    this.originalSentence,
    this.documentId,
  });

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  bool _isLoading = false;
  OverlayEntry? _overlayEntry;
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String _currentSpeakingText = '';
  Map<String, dynamic>? _dictionaryData;
  Map<String, dynamic>? _wordData;
  bool _isWordSaved = false;
  // 炎マーク状態管理用のセット
  // Set<String> _sparkedWords = {};
  // examples データ（List<List<Example>>形式）
  List<List<Map<String, dynamic>>> _examples = [];
  
  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // チュートリアル用
  final GlobalKey _saveButtonKey = GlobalKey();
  BuildContext? _showcaseContext;

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

  // analysisDataからexamplesを読み込む
  void _loadExamplesFromAnalysisData() {
    try {
      final analysisData = widget.analysisData;
      print('🔍 Loading examples from analysis data');
      print('🔍 Analysis data: $analysisData');
      
      if (analysisData != null && analysisData['examples'] != null) {
        final dynamic rawExamples = analysisData['examples'];
        print('🔍 Raw examples: $rawExamples');
        print('🔍 Raw examples type: ${rawExamples.runtimeType}');
        
        if (rawExamples is List) {
          _examples = rawExamples.map<List<Map<String, dynamic>>>((meaningExamples) {
            print('🔍 Processing meaning examples: $meaningExamples');
            if (meaningExamples is List) {
              return meaningExamples.map<Map<String, dynamic>>((example) {
                return _convertToMap(example);
              }).toList();
            }
            return <Map<String, dynamic>>[];
          }).toList();
          
          print('🔍 Processed examples count: ${_examples.length}');
          print('🔍 Processed examples: $_examples');
        } else {
          print('🔍 Raw examples is not a List');
        }
      } else {
        print('🔍 No examples found in analysis data');
      }
    } catch (e) {
      print('🔍 Error loading examples: $e');
      // エラーの場合は空のリストを設定
      _examples = [];
    }
  }

  @override
  void initState() {
    super.initState();
    print('🔍 WordDetailPage initState');
    print('🔍 widget.analysisData: ${widget.analysisData}');
    print('🔍 widget.dictionaryId: ${widget.dictionaryId}');
    _initTts();
    _loadWordData();
    _markWordDetailVisited();
    
    // チュートリアルの表示（少し遅延させる）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _checkAndShowTutorial();
    });
  }
  
  // 単語詳細ページを訪問したことを記録
  Future<void> _markWordDetailVisited() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('word_detail_visited', true);
  }
  
  // チュートリアルを表示するかチェック
  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial = prefs.getBool('word_detail_save_tutorial_shown') ?? false;
    
    if (!hasShownTutorial && mounted && _showcaseContext != null) {
      ShowCaseWidget.of(_showcaseContext!).startShowCase([_saveButtonKey]);
      await prefs.setBool('word_detail_save_tutorial_shown', true);
    }
  }

  Future<void> _loadWordData() async {
    print('🔍 _loadWordData started');
    print('🔍 widget.dictionaryId: ${widget.dictionaryId}');
    
    if (widget.dictionaryId == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Firestore から dictionary データを取得
      final dictionaryDoc = await FirebaseFirestore.instance
          .collection('dictionary')
          .doc(widget.dictionaryId)
          .get();

      if (dictionaryDoc.exists) {
        _dictionaryData = dictionaryDoc.data();
        print('🔍 _dictionaryData loaded: ${_dictionaryData != null}');
        
        // 分析データと辞書データを結合
        _wordData = {
          ...widget.analysisData ?? {},
          ..._dictionaryData ?? {},
        };
        
        print('🔍 Before _loadExamplesFromAnalysisData');
        print('🔍 widget.analysisData: ${widget.analysisData}');
        
        // analysisDataからexamplesを取得
        _loadExamplesFromAnalysisData();
      }
      
      // 保存状態をチェック
      await _checkWordSavedStatus();
      // 炎マーク状態をチェック
      // await _loadSparkedWords();
    } catch (e) {
      _showMessage('辞書データの取得に失敗しました: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  // Future<void> _loadSparkedWords() async {
  //   try {
  //     final user = FirebaseAuth.instance.currentUser;
  //     if (user == null) return;
  //     
  //     final query = await FirebaseFirestore.instance
  //         .collection('user_words_sparked')
  //         .where('user_id', isEqualTo: user.uid)
  //         .get();
  //     
  //     setState(() {
  //       _sparkedWords = query.docs
  //           .map((doc) => doc.data()['word'] as String? ?? '')
  //           .where((word) => word.isNotEmpty)
  //           .toSet();
  //     });
  //   } catch (e) {
  //     // エラーは無視（UI には影響しない）
  //   }
  // }

  Future<void> _checkWordSavedStatus() async {
    if (widget.dictionaryId == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _isWordSaved = false;
        return;
      }
      final query = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: user.uid)
          .where('word_id', isEqualTo: widget.dictionaryId)
          .limit(1)
          .get();
      _isWordSaved = query.docs.isNotEmpty;
    } catch (e) {
      _isWordSaved = false;
    }
  }

  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    
    // TTS設定
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // 話速（0.0〜1.0）
    await _flutterTts.setVolume(1.0); // 音量（0.0〜1.0）
    await _flutterTts.setPitch(1.0); // ピッチ（0.5〜2.0）
    
    // コールバック設定
    _flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });
    
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _currentSpeakingText = '';
      });
    });
    
    _flutterTts.setErrorHandler((message) {
      setState(() {
        _isSpeaking = false;
        _currentSpeakingText = '';
      });
    });
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking) {
      await _flutterTts.stop();
    }
    
    setState(() {
      _currentSpeakingText = text;
    });
    
    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
      _currentSpeakingText = '';
    });
  }

  Widget _buildSpeakerButton(String text, {double size = 24}) {
    final isCurrentlySpeaking = _isSpeaking && _currentSpeakingText == text;
    
    return IconButton(
      onPressed: () {
        if (isCurrentlySpeaking) {
          _stopSpeaking();
        } else {
          _speak(text);
        }
      },
      icon: Icon(
        isCurrentlySpeaking ? Icons.volume_off : Icons.volume_up,
        size: size,
        color: isCurrentlySpeaking ? Colors.red : Colors.blue,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: size + 8,
        minHeight: size + 8,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            '読み込み中...',
            style: TextStyle(
              fontSize: 18,
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
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_wordData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'エラー',
            style: TextStyle(
              fontSize: 18,
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
        ),
        body: const Center(
          child: Text('単語データを読み込めませんでした'),
        ),
      );
    }

    final String originalWord = _wordData!['original_word'] ?? '';
    final String baseWord = _wordData!['base_word'] ?? _wordData!['word'] ?? '';
    final String wordForm = _wordData!['word_form'] ?? '';
    final String partOfSpeech = _wordData!['part_of_speech'] ?? '';
    final String pronunciation = _wordData!['pronunciation'] ?? '';
    final String contextRole = _wordData!['context_role'] ?? '';
    final String etymology = _wordData!['etymology'] ?? '';
    final List meanings = _wordData!['meanings'] ?? [];
    final List derivatives = _wordData!['derivatives'] ?? [];

    return ShowCaseWidget(
      builder: (context) {
        // ShowCaseWidget内のコンテキストを保存
        _showcaseContext = context;
        return WillPopScope(
          onWillPop: () async {
            // 戻る時にtrueを返す（チュートリアルトリガー用）
            Navigator.pop(context, true);
            return false; // WillPopScopeの処理を止める（すでにpopしたため）
          },
          child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          originalWord.isNotEmpty ? originalWord : baseWord,
          style: const TextStyle(
            fontSize: 18,
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
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            originalWord.isNotEmpty ? originalWord : baseWord,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Georgia',
                            ),
                          ),
                        ),
                        // _buildSparkButton(originalWord.isNotEmpty ? originalWord : baseWord),
                        _buildSpeakerButton(originalWord.isNotEmpty ? originalWord : baseWord),
                      ],
                    ),
                    if (baseWord != originalWord && originalWord.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '原形: $baseWord',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // _buildSparkButton(baseWord, size: 18),
                          _buildSpeakerButton(baseWord, size: 18),
                        ],
                      ),
                    if (wordForm.isNotEmpty)
                      Text(
                        '活用形: $wordForm',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (partOfSpeech.isNotEmpty)
                      Text(
                        partOfSpeech,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (pronunciation.isNotEmpty)
                      Text(
                        pronunciation,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // 保存数をリアルタイム取得
                    if (widget.dictionaryId != null) ...[
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('dictionary')
                            .doc(widget.dictionaryId!)
                            .snapshots(),
                        builder: (context, snapshot) {
                          int savedUsers = 0;
                          if (snapshot.hasData && snapshot.data!.data() != null) {
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            savedUsers = data['saved_users'] ?? 0;
                          }
                          return Text(
                            '保存数: $savedUsers',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // 文脈分析から語源まで
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      // 文脈分析
                      if (contextRole.isNotEmpty) ...[
                        const Text(
                          '文脈での役割',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(6),
                             color: const Color(0xFFeafff4),
                           ),
                          child: Text(
                            contextRole,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                      
                      // 意味一覧
                      if (meanings.isNotEmpty) ...[
                        const Text(
                          '意味・用法',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...meanings.asMap().entries.map((entry) {
                          final index = entry.key;
                          final meaning = entry.value;
                          // 該当する意味のexamplesを取得
                          final meaningExamples = index < _examples.length ? _examples[index] : <Map<String, dynamic>>[];
                          print('🔍 Building meaning card $index: examples count = ${meaningExamples.length}');
                          print('🔍 Meaning examples for index $index: $meaningExamples');
                          return _buildMeaningCard(meaning, index + 1, meaningExamples);
                        }),
                      ],
                      const Divider(),
                      const SizedBox(height: 40),
                      // 派生語
                      if (derivatives.isNotEmpty) ...[
                        const Text(
                          '派生語',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...derivatives.map((derivative) => _buildDerivativeCard(derivative)),
                        const SizedBox(height: 60),
                      ],
                      
                      // 語源
                      if (etymology.isNotEmpty) ...[
                        const Text(
                          '語源',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: const Color(0xFFfff4ea),
                          ),
                          child: MarkdownBody(
                            data: etymology,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(fontSize: 14, height: 1.5),
                              strong: const TextStyle(fontWeight: FontWeight.bold),
                              em: const TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                
                // 保存ボタンのためのスペース
                const SizedBox(height: 100),
              ],
            ),
          ),
          
          // 保存ボタンと編集ボタン (固定位置)
          if (widget.dictionaryId != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: Row(
                  children: [
                    Expanded(
                      child: Showcase(
                        key: _saveButtonKey,
                        title: '覚えたい単語は保存しよう',
                        description: '保存した単語はいつでも見返せます',
                        targetPadding: const EdgeInsets.all(8),
                        child: ElevatedButton.icon(
                          onPressed: () => _isWordSaved ? _removeWordFromWordlist() : _showSaveWordBottomSheet(),
                          icon: Icon(_isWordSaved ? Icons.delete : Icons.save),
                          label: Text(_isWordSaved ? '保存解除' : '単語を保存'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isWordSaved) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showEditMeaningsBottomSheet,
                          icon: const Icon(Icons.edit),
                          label: const Text('編集'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
          ),
        );
      },
    );
  }

  Future<void> _showSaveWordBottomSheet() async {
    if (widget.dictionaryId == null || _wordData == null) return;
    
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SaveWordPage(
          dictionaryId: widget.dictionaryId!,
          wordData: _wordData!,
          examples: _examples,
          initialListId: widget.listId,
          documentId: widget.documentId,
        ),
      ),
    );

    if (result == true) {
      // 保存成功
      setState(() {
        _isWordSaved = true;
      });
      _showMessage('✅ 単語を保存しました', isSuccess: true);
    }
  }

  Future<void> _removeWordFromWordlist() async {
    if (widget.dictionaryId == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }
      // user_wordsコレクションから該当ドキュメントを削除
      final query = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: user.uid)
          .where('word_id', isEqualTo: widget.dictionaryId)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        _showMessage('この単語は保存されていません');
        setState(() {
          _isWordSaved = false;
        });
        return;
      }
      await FirebaseFirestore.instance
          .collection('user_words')
          .doc(query.docs.first.id)
          .delete();
      // dictionaryコレクションのsaved_usersを1減少
      final dictionaryRef = FirebaseFirestore.instance
          .collection('dictionary')
          .doc(widget.dictionaryId);
      await dictionaryRef.update({
        'saved_users': FieldValue.increment(-1),
      });
      if (mounted) {
        setState(() {
          _isWordSaved = false;
        });
        _showMessage('✅ 保存を解除しました', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('❌ 保存解除に失敗しました: $e');
      }
    }
  }

  Future<void> _showEditMeaningsBottomSheet() async {
    if (widget.dictionaryId == null) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }

      // user_wordsからドキュメントを取得
      final query = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: user.uid)
          .where('word_id', isEqualTo: widget.dictionaryId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showMessage('この単語は保存されていません');
        return;
      }

      final userWordDoc = query.docs.first;
      final userWordData = userWordDoc.data();
      final meanings = userWordData['meanings'] ?? [];

      if (meanings.isEmpty) {
        _showMessage('編集できる意味がありません');
        return;
      }

      // ボトムシートを表示
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: EditMeaningsBottomSheet(
            userWordId: userWordDoc.id,
            initialMeanings: meanings,
          ),
        ),
      );

      // 編集が成功した場合、データを再読み込み
      if (result == true) {
        await _loadWordData();
      }
    } catch (e) {
      _showMessage('❌ エラーが発生しました: $e');
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

  // 画面全体を覆うローディング画面を表示
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
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '処理中です...\nしばらくお待ちください',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ローディング画面を非表示
  void _hideLoadingOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideLoadingOverlay();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _onWordTapped(String word, {String? contextSentence}) async {
    if (word.trim().isEmpty || word.length < 2) return;
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });
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
        'sentence': contextSentence ?? '',
      });
      
      // 安全な型キャスト
      final dynamic rawData = result.data;
      print('🔍 _onWordTapped: Raw data: $rawData');
      final responseData = _convertToMap(rawData);

      if (responseData['success'] == true) {
        // ネストしたデータも安全に変換
        final analysisData = _convertToMap(responseData['data']);
        final String dictionaryId = analysisData['dictionary_id'] ?? '';
        
        print('🔍 _onWordTapped: Full response data: $responseData');
        print('🔍 _onWordTapped: Analysis data: $analysisData');
        print('🔍 _onWordTapped: Examples in analysis data: ${analysisData['examples']}');
        
        if (mounted && dictionaryId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WordDetailPage(
                dictionaryId: dictionaryId,
                analysisData: analysisData,
                listId: widget.listId,
                originalSentence: widget.originalSentence,
                documentId: widget.documentId,
              ),
            ),
          );
        } else {
          _showMessage('❌ 単語の解析データが不正です');
        }
      } else {
        _showMessage('❌ 単語の解析に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ 単語の解析に失敗しました';
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
    } catch (e) {
      _showMessage('❌ エラーが発生しました: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      _hideLoadingOverlay();
    }
  }

  Widget _buildMeaningCard(Map<String, dynamic> meaning, int index, List<Map<String, dynamic>> examples) {
    final String definition = meaning['definition'] ?? '';
    final String partOfSpeech = meaning['part_of_speech'] ?? '';
    final String nuance = meaning['nuance'] ?? '';
    final List collocations = meaning['collocations'] ?? [];
    final List synonyms = meaning['synonyms'] ?? [];
    
    print('🔍 _buildMeaningCard: index=$index, examples.length=${examples.length}');
    print('🔍 _buildMeaningCard: examples=$examples');

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(
                    '$index. $definition',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
              ),
              if (partOfSpeech.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade300),
                    ),
                    child: Text(
                      partOfSpeech,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
            ],
          ),
          if (nuance.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFeaf4ff),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '💡 $nuance',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              ),
            ),
          ],
          
          // 例文
          if (examples.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text(
                '例文:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: examples.map((example) => _buildExampleItem(example)).toList(),
              ),
            ),
          ],
          
          // コロケーション (タップ機能なし)
          if (collocations.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text(
                'よく使われる表現 :',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: collocations.map((collocation) => _buildCollocationItem(collocation)).toList(),
              ),
            ),
          ],
          
          // 類義語 (タップ可能)
          if (synonyms.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text(
                '類義語 :',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: synonyms.map((synonym) => _buildSynonymItem(synonym)).toList(),
              ),
            ),
          ],
          
        ],
      ),
    );
  }

  Widget _buildExampleItem(Map<String, dynamic> example) {
    final String originalText = example['original'] ?? '';
    final String translation = example['translation'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 例文と音声ボタンを並べて配置
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  runSpacing: 6.0, // 行間を空ける
                  children: _buildTappableWords(originalText, contextSentence: originalText),
                ),
              ),
              _buildSpeakerButton(originalText, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            translation,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTappableWords(String text, {String? contextSentence}) {
    // 句読点を含めてスペース区切りで分解
    final RegExp wordRegex = RegExp(r'\S+');
    final Iterable<RegExpMatch> matches = wordRegex.allMatches(text);
    
    List<Widget> widgets = [];
    int lastEnd = 0;
    
    for (final match in matches) {
      // マッチ前のスペースを追加
      if (match.start > lastEnd) {
        widgets.add(Text(
          text.substring(lastEnd, match.start),
          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
        ));
      }
      
      final word = match.group(0)!;
      // 句読点を除去して英単語のみを抽出
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      
      if (cleanWord.isNotEmpty && cleanWord.length >= 1) {
        // タップ可能な単語
        widgets.add(
          GestureDetector(
            onTap: () => _onWordTapped(cleanWord, contextSentence: contextSentence),
            child: Text(
              word,
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Georgia',
                color: Colors.black,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        );
      } else {
        // 句読点や短い文字列はそのまま表示
        widgets.add(Text(
          word,
          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
        ));
      }
      
      lastEnd = match.end;
    }
    
    // 残りのテキストを追加
    if (lastEnd < text.length) {
      widgets.add(Text(
        text.substring(lastEnd),
        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
      ));
    }
    
    return widgets;
  }

  Widget _buildCollocationItem(Map<String, dynamic> collocation) {
    final String phrase = collocation['phrase'] ?? '';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${phrase} → ${collocation['translation'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontFamily: 'Georgia'),
            ),
          ),
          // _buildSparkButton(phrase, size: 16),
        ],
      ),
    );
  }

  Widget _buildSynonymItem(Map<String, dynamic> synonym) {
    final String word = synonym['word'] ?? '';
    final String nuance = synonym['nuance'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _onWordTapped(word),
                  child: Text(
                    word,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      decoration: TextDecoration.underline,
                      fontFamily: 'Georgia',
                    ),
                  ),
                ),
              ),
              // _buildSparkButton(word, size: 16),
              _buildSpeakerButton(word, size: 16),
            ],
          ),
          if (nuance.isNotEmpty)
            Text(
              nuance,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Widget _buildDerivativeCard(Map<String, dynamic> derivative) {
    final String derivativeWord = derivative['word'] ?? '';
    final String partOfSpeech = derivative['part_of_speech'] ?? '';
    final String meaning = derivative['translation'] ?? '';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 一行目: 単語、炎マーク、再生マーク、品詞
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _onWordTapped(derivativeWord),
                  child: Text(
                    derivativeWord,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                      fontFamily: 'Georgia'
                    ),
                  ),
                ),
              ),
              // _buildSparkButton(derivativeWord, size: 18),
              _buildSpeakerButton(derivativeWord, size: 18),
              // const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade300),
                ),
                child: Text(
                  partOfSpeech,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple.shade700,
                  ),
                ),
              ),
            ],
          ),
          // 二行目: 意味
          if (meaning.isNotEmpty) ...[
            Text(
              meaning,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
} 