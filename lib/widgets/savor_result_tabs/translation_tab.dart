import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../pages/conversation_page.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/admob_service.dart';

class TranslationTab extends StatefulWidget {
  final Map<String, dynamic> savorResult;
  final String documentId;

  const TranslationTab({
    super.key,
    required this.savorResult,
    required this.documentId,
  });

  @override
  State<TranslationTab> createState() => _TranslationTabState();
}

class _TranslationTabState extends State<TranslationTab> {
  List<bool> _translationVisibility = [];
  bool _showAllTranslations = false;
  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  // インタースティシャル広告
  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    final translations = widget.savorResult['sentence_translations'];
    if (translations is List) {
      _translationVisibility = List.filled(translations.length, false);
    }
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  // インタースティシャル広告を読み込み
  void _loadInterstitialAd() async {
    await AdMobService.createInterstitialAd(
      onAdLoaded: (ad) {
        setState(() {
          _interstitialAd = ad;
          _isAdLoaded = true;
        });
      },
      onAdFailedToLoad: (error) {
        setState(() {
          _isAdLoaded = false;
        });
      },
    );
  }

  // インタースティシャル広告を表示
  void _showInterstitialAd() {
    if (_isAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadInterstitialAd(); // 次の広告を読み込み
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadInterstitialAd(); // 次の広告を読み込み
        },
      );
      _interstitialAd!.show();
    }
  }

  void _toggleAllTranslations() {
    setState(() {
      _showAllTranslations = !_showAllTranslations;
      for (int i = 0; i < _translationVisibility.length; i++) {
        _translationVisibility[i] = _showAllTranslations;
      }
    });
  }

  void _toggleTranslation(int index) {
    setState(() {
      _translationVisibility[index] = !_translationVisibility[index];
      // 全て表示されている場合は_showAllTranslationsをtrueに、そうでなければfalseに
      _showAllTranslations = _translationVisibility.every((visible) => visible);
    });
  }

  Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  // Firebase Functionsのgenerate-responseを呼び出し
  Future<void> _callGenerateResponse(String roomId) async {
    try {
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



    @override
  Widget build(BuildContext context) {
    final translations = widget.savorResult['sentence_translations'];
    final userId = widget.savorResult['user_id'] ?? '';
    
    if (translations == null || translations is! List) {
      return const Center(child: Text('翻訳情報がありません'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // 一括切り替えボタン
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8), // 縦のパディングを小さく
            child: ElevatedButton.icon(
              onPressed: _toggleAllTranslations,
              icon: Icon(_showAllTranslations ? Icons.visibility_off : Icons.visibility),
              label: Text(_showAllTranslations ? '全ての翻訳を非表示' : '全ての翻訳を表示'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), // ボタン自体のパディングを狭く
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 翻訳リスト
          Expanded(
            child: ListView.builder(
              itemCount: translations.length,
              itemBuilder: (context, index) {
                final translation = translations[index];
                if (translation is Map<String, dynamic>) {
                  final rawSentence = translation['raw'] ?? '';
                  final isTranslationVisible = _translationVisibility[index];
                  
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 英文（タップ可能）
                        InkWell(
                          onTap: () => _toggleTranslation(index),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              translation['raw'] ?? '',
                              style: const TextStyle(fontSize: 15, height: 1.4),
                            ),
                          ),
                        ),
                        // 翻訳（条件付き表示）
                        if (isTranslationVisible)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withOpacity(0.1),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    translation['translation'] ?? '',
                                    style: const TextStyle(fontSize: 14, height: 1.4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  child: const Text('解説'),
                                  onPressed: () async {
                                    final firestore = FirebaseFirestore.instance;
                                    final now = DateTime.now();
                                    await _ensureSignedIn();
                                    final authUser = FirebaseAuth.instance.currentUser;
                                    final effectiveUserId = authUser?.uid ?? userId;
                                    // ルーム作成
                                    final roomRef = await firestore.collection('user_rooms').add({
                                      'created_at': now,
                                      'document_id': widget.documentId,
                                      'title': rawSentence,
                                      'user_id': effectiveUserId,
                                    });
                                    if (context.mounted) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ConversationPage(
                                            roomId: roomRef.id,
                                            title: rawSentence,
                                          ),
                                        ),
                                      );
                                    }
                                    // 以降の処理はバックグラウンドで
                                    final messageContent = '「$rawSentence」の文法構造を詳しく説明してください。';
                                    firestore.collection('messages').add({
                                      'content': messageContent,
                                      'created_at': now,
                                      'role': 'user',
                                      'room_id': roomRef.id,
                                      'user_id': effectiveUserId,
                                    });
                                    _callGenerateResponse(roomRef.id);

                                    // 1秒待ってからインタースティシャル広告を表示
                                    Future.delayed(const Duration(seconds: 2), () {
                                      _showInterstitialAd();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(60, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    textStyle: const TextStyle(fontSize: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
} 