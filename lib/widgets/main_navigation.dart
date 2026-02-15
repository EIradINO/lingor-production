import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/home_page.dart';
import '../pages/documents_page.dart';
import '../pages/dictionary_page.dart';
import '../pages/profile_page.dart';
import 'custom_navigation_bar.dart';
import 'global_loading_manager.dart';

// 通知からタブを切り替えるためのコントローラー
class MainNavigationController {
  static void Function(int)? _changeTabCallback;
  
  static void registerCallback(void Function(int) callback) {
    _changeTabCallback = callback;
  }
  
  static void changeTab(int index) {
    _changeTabCallback?.call(index);
  }
}

class MainNavigationScreen extends StatefulWidget {
  final User user;
  final VoidCallback onSignOut;

  const MainNavigationScreen({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 1;
  final GlobalLoadingManager _loadingManager = GlobalLoadingManager();
  
  late final List<Widget> _pages;
  final List<String> _pageTitles = ['ホーム', 'ドキュメント', 'ドキュメント', '質問', 'プロフィール'];
  
  // チュートリアル用のGlobalKey
  final GlobalKey _plusButtonKey = GlobalKey();
  
  // ShowCaseWidget内のBuildContextを保存
  BuildContext? _showcaseContext;
  
  // チュートリアルを表示するかチェック
  Future<void> _checkAndShowTutorial() async {
    // showcaseContextがない場合は表示しない
    if (_showcaseContext == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial = prefs.getBool('navigation_tutorial_shown') ?? false;
    
    if (!hasShownTutorial && mounted) {
      // +ボタンをハイライト
      ShowCaseWidget.of(_showcaseContext!).startShowCase([_plusButtonKey]);
      // フラグを保存
      await prefs.setBool('navigation_tutorial_shown', true);
    }
  }
  
  // ユーザーデータを取得するStream（Gemsとプラン）
  Stream<Map<String, dynamic>> _getUserDataStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        return {
          'gems': data?['gems'] ?? 0,
          'plan': data?['plan'] ?? 'free',
        };
      }
      return {'gems': 0, 'plan': 'free'};
    });
  }

  // ユーザープランを取得
  Future<String> _getUserPlan() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      
      if (doc.exists) {
        return doc.data()?['plan'] ?? 'free';
      }
      return 'free';
    } catch (e) {
      return 'free';
    }
  }

  // GEM配布情報ダイアログを表示
  void _showGemInfoDialog() async {
    final plan = await _getUserPlan();
    
    String planDisplayName;
    String gemDistribution;
    String distributionTiming;
    Color planColor;
    
    switch (plan.toLowerCase()) {
      case 'free':
        planDisplayName = 'Freeプラン';
        gemDistribution = '月100個';
        distributionTiming = '毎月1日に配布';
        planColor = Colors.grey;
        break;
      case 'standard':
        planDisplayName = 'Standardプラン';
        gemDistribution = '無制限';
        distributionTiming = '使い放題';
        planColor = Colors.green;
        break;
      case 'pro':
        planDisplayName = 'Proプラン';
        gemDistribution = '無制限';
        distributionTiming = '使い放題';
        planColor = Colors.blue;
        break;
      default:
        planDisplayName = 'Freeプラン';
        gemDistribution = '月100個';
        distributionTiming = '毎月1日に配布';
        planColor = Colors.grey;
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.diamond,
                color: Colors.orange.shade600,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text('GEM配布について'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: planColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: planColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: planColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          planDisplayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: planColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.diamond,
                          color: Colors.orange.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          gemDistribution,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      distributionTiming,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (plan == 'standard' || plan == 'pro')
                    ? 'このプランではGEMを消費せずに機能を利用できます。'
                    : 'GEMは文書の解析や音声合成などの機能で使用されます。',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(user: widget.user),
      DocumentsPage(key: documentsPageKey),
      DocumentsPage(key: documentsPageKey), // プラスボタン用（実際は使用されない）
      DictionaryPage(user: widget.user),
      ProfilePage(user: widget.user, onSignOut: widget.onSignOut),
    ];
    
    // 通知からタブを切り替えるためのコールバックを登録
    MainNavigationController.registerCallback((index) {
      if (mounted) {
        setState(() {
          _selectedIndex = index;
        });
      }
    });
    
    // チュートリアルを表示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowTutorial();
    });
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      // プラスボタンが押された場合は、DocumentsPageのファイル選択ダイアログを開く
      setState(() {
        _selectedIndex = 1; // ドキュメントページに切り替える
      });
      // ファイル選択ダイアログを開く
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = documentsPageKey.currentState;
        if (state != null) {
          (state as dynamic).showFileSelectionDialog();
        }
      });
      return;
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      onFinish: () {
        // +ボタンのチュートリアルが終了したら、DocumentsPageのチュートリアルを開始
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final state = documentsPageKey.currentState;
          if (state != null && mounted) {
            (state as dynamic).startDocumentTutorial();
          }
        });
      },
      builder: (context) {
        // ShowCaseWidget内のcontextを保存
        _showcaseContext = context;
        return ValueListenableBuilder<bool>(
          valueListenable: _loadingManager.isLoadingNotifier,
          builder: (context, isLoading, child) {
            return ValueListenableBuilder<String?>(
              valueListenable: _loadingManager.loadingMessageNotifier,
              builder: (context, loadingMessage, _) {
                return Stack(
                  children: [
                    Scaffold(
                      backgroundColor: Colors.grey[50],
                      body: Column(
                        children: [
                          // カスタムヘッダー
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.only(
                              top: MediaQuery.of(context).padding.top + 8,
                              left: 24,
                              right: 24,
                              bottom: 12,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey,
                                  width: 1.0,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // ページタイトル
                                Text(
                                  _pageTitles[_selectedIndex == 2 ? 1 : _selectedIndex],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                // Gems表示
                                StreamBuilder<Map<String, dynamic>>(
                                  stream: _getUserDataStream(),
                                  builder: (context, snapshot) {
                                    final data = snapshot.data ?? {'gems': 0, 'plan': 'free'};
                                    final gems = data['gems'];
                                    final plan = data['plan'] as String;
                                    final isUnlimited = plan == 'standard' || plan == 'pro';
                                    
                                    return GestureDetector(
                                      onTap: _showGemInfoDialog,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.diamond,
                                              color: Colors.orange.shade600,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isUnlimited ? '∞' : gems.toString(),
                                              style: TextStyle(
                                                fontSize: isUnlimited ? 18 : 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          // ページコンテンツ
                          Expanded(
                            child: _pages[_selectedIndex == 2 ? 1 : _selectedIndex],
                          ),
                        ],
                      ),
                      extendBody: true,
                      bottomNavigationBar: CustomNavigationBar(
                        currentIndex: _selectedIndex == 2 ? 1 : _selectedIndex,
                        onTap: _onItemTapped,
                        plusButtonKey: _plusButtonKey,
                      ),
                    ),
                    if (isLoading)
                      Container(
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
                                if (loadingMessage != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    loadingMessage,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
} 