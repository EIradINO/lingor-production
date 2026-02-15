import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/admob_service.dart';

class SelectionBottomSheet extends StatefulWidget {
  final String selectedText;
  final Function(String, String, String) onQuickAction; // AIモデルパラメータを追加
  final Function(String, String, String) onCustomQuestion; // AIモデルパラメータを追加
  final String userPlan; // ユーザープラン情報を追加

  const SelectionBottomSheet({
    super.key,
    required this.selectedText,
    required this.onQuickAction,
    required this.onCustomQuestion,
    required this.userPlan,
  });

  @override
  State<SelectionBottomSheet> createState() => _SelectionBottomSheetState();
}

class _SelectionBottomSheetState extends State<SelectionBottomSheet> {
  final TextEditingController _textController = TextEditingController();
  String _selectedModel = 'fast'; // デフォルトは高速
  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    // プランに応じてモデルを設定
    _selectedModel = _getModelFromPlan();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  String _getModelFromPlan() {
    switch (widget.userPlan) {
      case 'pro':
        return 'smart';
      case 'free' || 'adfree':
      default:
        return 'fast';
    }
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





  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // ヘッダー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '選択されたテキスト',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 選択されたテキスト表示
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                maxHeight: 150, // 最大高さを150pxに制限
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.selectedText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            
            // 3つのボタン
            Column(
              children: [
                _buildActionButton(
                  icon: Icons.school,
                  title: '文法を知りたい',
                  subtitle: '全体の文脈を踏まえた文法構造を解説',
                  color: Colors.green,
                  onTap: () {
                    widget.onQuickAction(widget.selectedText, 'grammar', _selectedModel);
                    _showInterstitialAd();
                  },
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.translate,
                  title: '意味を知りたい',
                  subtitle: '熟語やイディオムとしての意味を解説',
                  color: Colors.blue,
                  onTap: () => widget.onQuickAction(widget.selectedText, 'meaning', _selectedModel),
                ),
                const SizedBox(height: 12),
              ],
            ),
            const SizedBox(height: 24),
            
            // カスタムテキストフィールド
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AIへの質問',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: '質問を入力...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        if (_textController.text.trim().isNotEmpty) {
                          widget.onCustomQuestion(widget.selectedText, _textController.text.trim(), _selectedModel);
                          _showInterstitialAd();
                        }
                      },
                      icon: const Icon(Icons.send),
                    ),
                  ),
                  maxLines: 2,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      widget.onCustomQuestion(widget.selectedText, value.trim(), _selectedModel);
                      _showInterstitialAd();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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
