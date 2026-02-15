import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

// コールバック型定義
typedef OnTranscriptionSaved = void Function(String documentId, String transcription);

class TranscriptionEditPage extends StatefulWidget {
  final String documentId;
  final String title;
  final String initialTranscription;
  final OnTranscriptionSaved? onTranscriptionSaved;

  const TranscriptionEditPage({
    super.key,
    required this.documentId,
    required this.title,
    required this.initialTranscription,
    this.onTranscriptionSaved,
  });

  @override
  State<TranscriptionEditPage> createState() => _TranscriptionEditPageState();
}

class _TranscriptionEditPageState extends State<TranscriptionEditPage> {
  late TextEditingController _transcriptionController;
  bool _isSaving = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _currentGems = 0;
  int _requiredGems = 0;
  bool _isLoadingGems = true;
  String? _userPlan; // ユーザーのプラン情報
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  late FocusNode _textFieldFocusNode;
  bool _isTextFieldFocused = false;

  Map<String, dynamic> _convertToMap(dynamic data) {
    if (data == null) {
      return <String, dynamic>{};
    }
    
    if (data is Map<String, dynamic>) {
      return data;
    }
    
    if (data is Map) {
      final result = <String, dynamic>{};
      data.forEach((key, value) {
        result[key.toString()] = _convertValue(value);
      });
      return result;
    }
    
    // その他の場合は空のマップを返す
    return <String, dynamic>{};
  }

  // ネストされた値の変換メソッド
  dynamic _convertValue(dynamic value) {
    if (value == null) {
      return null;
    }
    
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, val) {
        result[key.toString()] = _convertValue(val);
      });
      return result;
    }
    
    if (value is List) {
      return value.map((item) => _convertValue(item)).toList();
    }
    
    return value;
  }

  @override
  void initState() {
    super.initState();
    _transcriptionController = TextEditingController(text: widget.initialTranscription);
    _textFieldFocusNode = FocusNode();
    _textFieldFocusNode.addListener(_onFocusChange);
    _loadCurrentGems();
    _transcriptionController.addListener(_updateRequiredGems);
    _updateRequiredGems(); // 初期値を計算
  }

  @override
  void dispose() {
    _transcriptionController.removeListener(_updateRequiredGems);
    _transcriptionController.dispose();
    _textFieldFocusNode.removeListener(_onFocusChange);
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentGems() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists) {
          setState(() {
            _currentGems = doc.data()?['gems'] ?? 0;
            _userPlan = doc.data()?['plan'] as String?;
            _isLoadingGems = false;
          });
        } else {
          setState(() {
            _currentGems = 0;
            _userPlan = null;
            _isLoadingGems = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _currentGems = 0;
        _userPlan = null;
        _isLoadingGems = false;
      });
    }
  }

  void _updateRequiredGems() {
    final text = _transcriptionController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _requiredGems = 0;
      });
    } else {
      final wordCount = text.split(RegExp(r'\s+')).length;
      setState(() {
        _requiredGems = (wordCount / 10).ceil();
      });
    }
  }

  bool get _isPremiumPlan {
    return _userPlan == 'standard' || _userPlan == 'pro';
  }

  void _onFocusChange() {
    setState(() {
      _isTextFieldFocused = _textFieldFocusNode.hasFocus;
    });
  }

  void _showGemShortageDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Gemが不足しています'),
          content: Text('必要なGem: $_requiredGems\n現在のGem: $_currentGems\n\nGemを追加購入してください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    // プレミアムプランでない場合のみgem不足チェック
    if (!_isPremiumPlan && _currentGems < _requiredGems) {
      _showGemShortageDialog();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final transcription = _transcriptionController.text;

    // 改行ごとに段落を分割(空の行は無視)
    final paragraphs = transcription.split('\n').where((p) => p.trim().isNotEmpty).toList();

    // 200語を超える段落があるかチェック
    final hasLongParagraph = paragraphs.any((p) => p.split(RegExp(r'\s+')).length > 200);

    bool proceedToSave = true;
    if (hasLongParagraph) {
      // 注意ポップアップを表示
      proceedToSave = await _showLongParagraphWarning();
    }

    if (proceedToSave) {
      try {
        // Firestoreに文字起こしを保存
        await _firestore
            .collection('user_documents')
            .doc(widget.documentId)
            .update({
          'transcription': transcription,
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (widget.onTranscriptionSaved != null) {
          widget.onTranscriptionSaved!(widget.documentId, transcription);
        }

        _showMessage('✅ 文字起こしを保存しました', isSuccess: true);

        // Firebase FunctionsのsavorDocument関数を実行
        _callSavorFunction();
        
        // 解析開始後すぐに画面を閉じる
        Navigator.of(context).pop();

      } catch (e) {
        _showMessage('❌ 保存に失敗しました: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    } else {
      // ユーザーがキャンセルした場合
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<bool> _showLongParagraphWarning() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('注意'),
            ],
          ),
          content: const Text('200語を超える段落があります。処理が重くなる可能性がありますが、解析を開始しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('解析'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _callSavorFunction() async {
    // インタースティシャル広告を表示（iOSでのみ実行）
    _showInterstitialAd();

    try {
      final HttpsCallable callable = _functions.httpsCallable('savorDocument');
      final result = await callable.call({
        'documentId': widget.documentId,
      });
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        _showMessage('✅ ドキュメントの解析が完了しました', isSuccess: true);
        
        // 解析結果を自動的に表示するために、documents_savor_resultsから取得
        // 解析が完了しました
      } else {
        print('ドキュメント解析に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('ドキュメント解析でエラーが発生しました: $e');
    }
  }

  void _showInterstitialAd() async {
    await AdMobService.createInterstitialAd(
      onAdLoaded: (InterstitialAd ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            print('インタースティシャルの表示に失敗: $error');
          },
        );
        ad.show();
      },
      onAdFailedToLoad: (LoadAdError error) {
        print('インタースティシャルの読み込みに失敗: ${error.message}');
      },
    );
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '文字起こしを編集',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // 指示メッセージ（テキストフィールドにフォーカスがない時のみ表示）
          if (!_isTextFieldFocused)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.blue,
              child: const Text(
                '段落ごとに改行を入れたり\n正しく文字起こしされているかを確認してください',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _transcriptionController,
                      focusNode: _textFieldFocusNode,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: '文字起こし結果を編集してください...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(0),
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.5,
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            // プレミアムプランの場合は解析ボタンのみ、それ以外はGem情報と解析ボタンを横並びに表示
            if (!_isLoadingGems) ...[
              if (_isPremiumPlan) ...[
                // プレミアムプラン：解析ボタンのみ全幅で表示
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            '解析',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                // 通常プラン：Gem情報と解析ボタンを横並びに表示
                Row(
                  children: [
                    // Gem情報表示
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: _currentGems >= _requiredGems ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: _currentGems >= _requiredGems ? Colors.green.shade200 : Colors.red.shade200,
                        ),
                      ),
                      child: Text(
                        '消費GEM $_requiredGems/$_currentGems',
                        style: TextStyle(
                          fontSize: 14,
                          color: _currentGems >= _requiredGems ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 解析ボタン
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _isSaving || _isLoadingGems || _currentGems < _requiredGems ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  '解析',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              // ローディング中は従来通りの解析ボタンのみ表示
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '解析',
                    style: TextStyle(
                      fontSize: 24, // 1.5倍（16 × 1.5 = 24）
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 