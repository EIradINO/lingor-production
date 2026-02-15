import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'conversation_page.dart';
import 'word_detail_page.dart';
import '../services/admob_service.dart';

class DictionaryPage extends StatefulWidget {
  final User user;

  const DictionaryPage({
    super.key,
    required this.user,
  });

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _englishTextController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();
  bool _isWordSearching = false;
  bool _isCreatingRoom = false;

  // AdMob関連
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;

  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadInterstitialAd();
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
  void dispose() {
    _wordController.dispose();
    _englishTextController.dispose();
    _questionController.dispose();
    // バナー広告を解除
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() async {
    _bannerAd = await AdMobService.createBannerAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {
            _isBannerAdReady = true;
          });
        }
      },
      onAdFailedToLoad: (error) {
        print('バナー広告の読み込みに失敗: ${error.message}');
      },
    );
    
    // プランチェックの結果、広告が作成された場合のみ読み込み
    if (_bannerAd != null) {
      _bannerAd!.load();
    }
  }

  // インタースティシャル広告を読み込み
  void _loadInterstitialAd() async {
    await AdMobService.createInterstitialAd(
      onAdLoaded: (ad) {
        if (!mounted) return;
        setState(() {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        });
      },
      onAdFailedToLoad: (error) {
        if (!mounted) return;
        setState(() {
          _isInterstitialAdLoaded = false;
        });
      },
    );
  }

  // インタースティシャル広告を表示
  void _showInterstitialAd() {
    if (_isInterstitialAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: (_isBannerAdReady && _bannerAd != null)
          ? SafeArea(
              child: Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 単語検索セクション
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '検索',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _wordController,
                              decoration: const InputDecoration(
                                labelText: '単語またはイディオム',
                                hintText: '例: apple, give up, etc.',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _isWordSearching ? null : _searchWord,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isWordSearching
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('検索'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 区切り線
                Divider(
                  thickness: 1,
                  color: Colors.grey[300],
                ),
                
                const SizedBox(height: 24),
                
                // AI質問セクション
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AIへの質問',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _englishTextController,
                        decoration: const InputDecoration(
                          labelText: '質問したい英文',
                          hintText: '例: I want to improve my English speaking skills.',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      Divider(
                        thickness: 1,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      _buildActionButton(
                        icon: Icons.school,
                        title: '文法構造を知りたい',
                        color: Colors.green,
                        onTap: () async {
                          if (_englishTextController.text.trim().isEmpty) {
                            _showMessage('英文を入力してください');
                            return;
                          }
                          if (_isCreatingRoom) return;
                          _questionController.text = 'この英文の文法構造を詳しく教えてください。重要な文法ポイントも挙げてください。';
                          await _createRoom();
                          _showInterstitialAd();
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          labelText: '質問内容',
                          hintText: '例: この英文の文法について教えてください',
                          border: const OutlineInputBorder(),
                          suffixIcon: Container(
                            margin: const EdgeInsets.all(4),
                            child: ElevatedButton(
                              onPressed: _isCreatingRoom
                                  ? null
                                  : () async {
                                      await _createRoom();
                                      _showInterstitialAd();
                                    },
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(8),
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: _isCreatingRoom
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send, size: 20),
                            ),
                          ),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _searchWord() async {
    final word = _wordController.text.trim();
    
    if (word.isEmpty) {
      _showMessage('単語を入力してください');
      return;
    }

    setState(() {
      _isWordSearching = true;
    });

    try {
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('generateMeanings');
      
      final result = await callable.call({
        'word': word,
        'sentence': '',
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true && responseData['data'] != null) {
        // ネストしたデータも安全に変換
        final analysisData = _convertToMap(responseData['data']);
        final String dictionaryId = analysisData['dictionary_id'] ?? '';
        
        if (dictionaryId.isNotEmpty) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => WordDetailPage(
                  dictionaryId: dictionaryId,
                  analysisData: analysisData,
                ),
              ),
            );
          }
        } else {
          _showMessage('❌ 単語データの取得に失敗しました');
        }
      } else {
        _showMessage('❌ 単語の検索に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ 単語の検索に失敗しました';
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
      _showMessage('❌ 単語検索でエラーが発生しました: $e');
    } finally {
      setState(() {
        _isWordSearching = false;
      });
    }
  }

  String _generateTitle(String englishText) {
    final words = englishText.trim().split(' ');
    final firstWords = words.take(10).join(' ');
    return firstWords.length > 50 ? '${firstWords.substring(0, 50)}...' : firstWords;
  }

  Future<void> _createRoom() async {
    if (_englishTextController.text.trim().isEmpty) {
      _showMessage('英文を入力してください');
      return;
    }

    if (_questionController.text.trim().isEmpty) {
      _showMessage('質問内容を入力してください');
      return;
    }

    setState(() {
      _isCreatingRoom = true;
    });

    try {
      final englishText = _englishTextController.text.trim();
      final question = _questionController.text.trim();
      final title = _generateTitle(englishText);

      // ルームを作成
      final roomDoc = await FirebaseFirestore.instance
          .collection('user_rooms')
          .add({
        'title': title,
        'user_id': widget.user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      final roomId = roomDoc.id;

      // messagesコレクションにユーザーメッセージを作成
      final prompt = '$englishText\n\n$question';
      await FirebaseFirestore.instance
          .collection('messages')
          .add({
        'content': prompt,
        'role': 'user',
        'room_id': roomId,
        'user_id': widget.user.uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      // generate-responseを呼び出し（応答を待たない）
      _callGenerateResponse(roomId);

      // ConversationPageに遷移
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationPage(
              roomId: roomId,
              title: title,
            ),
          ),
        );
      }

      // 入力フィールドをクリア
      _englishTextController.clear();
      _questionController.clear();
      _showMessage('会話ルームを作成しました');
    } catch (e) {
      _showMessage('ルーム作成に失敗しました: $e');
    } finally {
      setState(() {
        _isCreatingRoom = false;
      });
    }
  }

  Future<void> _callGenerateResponse(String roomId) async {
    try {
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('generateResponse');
      
      await callable.call({
        'room_id': roomId,
      });
    } on FirebaseFunctionsException catch (_) {
      // 認証エラーやその他のFirebase Functionsエラー
      // ユーザー体験を阻害しないように続行
    } catch (_) {
      // その他のエラーが発生してもユーザー体験を阻害しないように続行
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
} 