import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/gem_purchase_widget.dart';

// コールバック型定義
typedef OnTextSubmitted = void Function(String title, String text);

class TextInputPage extends StatefulWidget {
  final OnTextSubmitted? onTextSubmitted;

  const TextInputPage({
    super.key,
    this.onTextSubmitted,
  });

  @override
  State<TextInputPage> createState() => _TextInputPageState();
}

class _TextInputPageState extends State<TextInputPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isSubmitting = false;
  int _currentGems = 0;
  int _requiredGems = 0;
  bool _isLoadingGems = true;
  String? _userPlan; // ユーザーのプラン情報

  @override
  void initState() {
    super.initState();
    _loadCurrentGems();
    _textController.addListener(_updateRequiredGems);
  }

  @override
  void dispose() {
    _textController.removeListener(_updateRequiredGems);
    _textController.dispose();
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
    final text = _textController.text.trim();
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

  void _showGemPurchaseBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const GemPurchaseWidget(),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // ボトムシートが閉じられた後にgem情報を再読み込み
      _loadCurrentGems();
    });
  }

  String _generateTitleFromText(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    final titleWords = words.take(10).toList();
    String title = titleWords.join(' ');
    
    // タイトルが長すぎる場合は省略
    if (title.length > 50) {
      title = '${title.substring(0, 47)}...';
    }
    
    return title.isNotEmpty ? title : 'テキスト';
  }

  Future<void> _handleSubmit() async {
    // プレミアムプランでない場合のみgem不足チェック
    if (!_isPremiumPlan && _currentGems < _requiredGems) {
      _showGemShortageDialog();
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final text = _textController.text.trim();
    final paragraphs = text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final hasLongParagraph = paragraphs.any((p) => p.split(RegExp(r'\s+')).length > 200);

    bool proceedToSubmit = true;
    if (hasLongParagraph) {
      proceedToSubmit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('注意'),
            content: const Text('200語を超える段落があります。処理が重くなる可能性がありますが、追加しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('追加する'),
              ),
            ],
          );
        },
      ) ?? false;
    }

    if (proceedToSubmit) {
      try {
        if (widget.onTextSubmitted != null) {
          final title = _generateTitleFromText(text);
          widget.onTextSubmitted!(title, text);
        }
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        // エラーハンドリングは親ウィジェットで行う
        rethrow;
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    } else {
      // ユーザーがキャンセルした場合
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('テキストを追加'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'ここにテキストを入力してください...',
                  border: InputBorder.none,
                  alignLabelWithHint: true,
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (value) {
                  setState(() {
                    // テキストが変更されたときにUIを更新
                  });
                },
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Gem情報表示（プレミアムプランでない場合のみ）
                if (!_isLoadingGems && !_isPremiumPlan) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: _currentGems >= _requiredGems ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: _currentGems >= _requiredGems ? Colors.green.shade200 : Colors.red.shade200,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '消費GEM $_requiredGems/$_currentGems',
                        style: TextStyle(
                          fontSize: 14,
                          color: _currentGems >= _requiredGems ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  // Gemが不足している場合に「gemを追加」ボタンを表示
                  if (_currentGems < _requiredGems && _requiredGems > 0) ...[
                    OutlinedButton.icon(
                      onPressed: _showGemPurchaseBottomSheet,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('gemを追加'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        minimumSize: const Size(double.infinity, 0),
                        side: BorderSide(color: Colors.red.shade300),
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                  ],
                ],
                ElevatedButton(
                  onPressed: _isSubmitting || 
                             _textController.text.trim().isEmpty || 
                             _isLoadingGems || 
                             (!_isPremiumPlan && _currentGems < _requiredGems)
                      ? null
                      : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          '追加して解析',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 