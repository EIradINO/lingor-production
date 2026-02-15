import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:lingosavor/pages/notification_test_page.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/admob_service.dart';
import '../widgets/my_wordlists_widget.dart';
import '../widgets/my_dictionary_widget.dart';
import '../widgets/my_questions_widget.dart';
import '../widgets/paywall_widget.dart';
import 'wordlist_subscription_page.dart';

// ユーザーデータモデルクラス
class UserData {
  final String userId;
  final String displayName;
  final String email;
  final String userName;
  final int gems;
  final DateTime createdAt;
  final String plan;
  final bool removeAds;

  UserData({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.userName,
    required this.gems,
    required this.createdAt,
    required this.plan,
    required this.removeAds,
  });

  factory UserData.fromFirestore(String docId, Map<String, dynamic> data) {
    return UserData(
      userId: docId,
      displayName: data['display_name'] ?? '',
      email: data['email'] ?? '',
      userName: data['user_name'] ?? '',
      gems: data['gems'] ?? 0,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      plan: data['plan'] ?? 'free',
      removeAds: data['remove_ads'] ?? false,
    );
  }
}

class ProfilePage extends StatefulWidget {
  final User user;
  final VoidCallback onSignOut;

  const ProfilePage({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // AdMob関連
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  
  // RevenueCat関連
  Offering? _upgradeDiscountOffering;
  Offering? _defaultOffering;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadOfferings();
  }
  
  /// RevenueCatのOfferingsを取得し、upgrade_discountとdefault offeringを探す
  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final upgradeDiscountOffering = offerings.all['upgrade_discount'];
      final defaultOffering = offerings.current;
      
      if (mounted) {
        setState(() {
          _upgradeDiscountOffering = upgradeDiscountOffering;
          _defaultOffering = defaultOffering;
        });
      }
    } catch (e) {
      print('Failed to load offerings: $e');
    }
  }

  @override
  void dispose() {
    // バナー広告を解除
    _bannerAd?.dispose();
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

  String _getPlanDisplayName(String plan) {
    switch (plan.toLowerCase()) {
      case 'free':
        return 'Freeプラン';
      case 'standard':
        return 'Standardプラン';
      case 'pro':
        return 'Proプラン';
      default:
        return 'Freeプラン';
    }
  }

  Color _getPlanColor(String plan) {
    switch (plan.toLowerCase()) {
      case 'free':
        return Colors.grey;
      case 'standard':
        return Colors.green;
      case 'pro':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          UserData? userData;
          
          if (userSnapshot.hasError) {
            return Center(
              child: Text('エラーが発生しました: ${userSnapshot.error}'),
            );
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (userSnapshot.hasData && userSnapshot.data!.exists) {
            userData = UserData.fromFirestore(
              userSnapshot.data!.id,
              userSnapshot.data!.data() as Map<String, dynamic>,
            );
          }

          return Column(
            children: [
              // プロフィール情報セクション
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // プロフィール画像
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 30,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ユーザー情報
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ユーザーID（user_name）
                          Row(
                            children: [
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'ID: ',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    TextSpan(
                                      text: userData?.userName ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'IDをコピー',
                                onPressed: () async {
                                  if (userData?.userName != null && userData!.userName.isNotEmpty) {
                                    await Clipboard.setData(ClipboardData(text: userData.userName));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('IDをコピーしました')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // プラン情報
                          Row(
                            children: [
                              Icon(
                                Icons.workspace_premium,
                                size: 16,
                                color: _getPlanColor(userData?.plan ?? 'free'),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getPlanColor(userData?.plan ?? 'free').withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _getPlanColor(userData?.plan ?? 'free').withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _getPlanDisplayName(userData?.plan ?? 'free'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _getPlanColor(userData?.plan ?? 'free'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 設定ボタンのみ残す
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showSettingsMenu(context, userData),
                      icon: Icon(
                        Icons.settings,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
              ),

              // リスト型メニューボタン
              Container(
                margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: const Text(
                        'My単語帳',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyWordlistsWidget(user: widget.user),
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey[200],
                      indent: 20,
                      endIndent: 20,
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: const Text(
                        'My辞書',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyDictionaryWidget(user: widget.user),
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey[200],
                      indent: 20,
                      endIndent: 20,
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: const Text(
                        'My質問',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyQuestionsWidget(user: widget.user),
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey[200],
                      indent: 20,
                      endIndent: 20,
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: Icon(
                        Icons.menu_book,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text(
                        '市販単語帳の登録',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '教材解析で使用する単語帳を選択',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WordlistSubscriptionPage(user: widget.user),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

            ],
          );
        },
      ),
    );
  }


  void _showSettingsMenu(BuildContext context, UserData? userData) {
    showModalBottomSheet(
          context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
        builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
                children: [
              const Text(
                '設定',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // プランをアップグレードボタン（統合版）
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close bottom sheet
                    
                    // remove_adsがtrueの場合はupgrade_discount、それ以外はdefault
                    final Offering? targetOffering = (userData?.removeAds == true)
                        ? _upgradeDiscountOffering
                        : _defaultOffering;
                    
                    if (targetOffering != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaywallPage(
                            offering: targetOffering,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('プラン情報の読み込み中です。しばらく待ってから再度お試しください。'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'プランをアップグレード',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              
              // ),
              
              // 通知テストボタン（開発モードでのみ表示・無効化）
              // if (kDebugMode)
              //   Container(
              //     width: double.infinity,
              //     margin: const EdgeInsets.only(bottom: 16),
              //     child: ElevatedButton(
              //       onPressed: () {
              //         Navigator.of(context).pop();
              //         Navigator.push(
              //           context,
              //           MaterialPageRoute(
              //             builder: (context) => const NotificationTestPage(),
              //           ),
              //         );
              //       },
              //       style: ElevatedButton.styleFrom(
              //         backgroundColor: Colors.purple[50],
              //         foregroundColor: Colors.purple[700],
              //         elevation: 0,
              //         shape: RoundedRectangleBorder(
              //           borderRadius: BorderRadius.circular(12),
              //           side: BorderSide(
              //             color: Colors.purple[200]!,
              //             width: 1,
              //           ),
              //         ),
              //         padding: const EdgeInsets.symmetric(vertical: 16),
              //       ),
              //       child: const Row(
              //         mainAxisAlignment: MainAxisAlignment.center,
              //         children: [
              //           Icon(Icons.notifications_active, size: 20),
              //           SizedBox(width: 8),
              //           Text(
              //             '通知テスト (開発者用)',
              //             style: TextStyle(
              //               fontSize: 16,
              //               fontWeight: FontWeight.w600,
              //             ),
              //           ),
              //         ],
              //       ),
              //     ),
              //   ),
              
              // サインアウトボタン
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onSignOut();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[50],
                    foregroundColor: Colors.grey[700],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'サインアウト',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // アカウント削除ボタン
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showDeleteAccountDialog(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red[700],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.red[200]!,
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'アカウント削除',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'アカウント削除',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: const Text(
            'アカウントを削除すると、すべてのデータが完全に削除され、復元できません。\n\n本当に削除しますか？',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'キャンセル',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAccount(context);
              },
              child: const Text(
                '削除',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    print('🔄 アカウント削除処理を開始します');
    
    BuildContext? dialogContext;
    
    try {
      // ローディングダイアログを表示
      if (context.mounted) {
        print('📱 ローディングダイアログを表示します');
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            dialogContext = context; // ダイアログのコンテキストを保存
            return const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('アカウントを削除中...'),
                ],
              ),
            );
          },
        );
      }

      print('🔥 Firebase Functionsを呼び出します');
      // Firebase Functionsを呼び出してアカウント削除
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('deleteAccount');
      final result = await callable.call();
      print('✅ Firebase Functions呼び出し成功: $result');

      // ローディングダイアログを確実に閉じる
      if (dialogContext != null && dialogContext!.mounted) {
        print('❌ ローディングダイアログを閉じます（保存されたコンテキスト使用）');
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      } else if (context.mounted) {
        print('❌ ローディングダイアログを閉じます（元のコンテキスト使用）');
        Navigator.of(context).pop();
      }

      // 成功メッセージを表示
      if (context.mounted) {
        print('💬 成功メッセージを表示します');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウントが削除されました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }

      print('🚪 サインアウト処理を呼び出します');
      // アカウント削除が成功したので、明示的にサインアウト処理を呼び出す
      // これによりFirebase Auth状態が確実にリセットされ、ログイン画面に戻る
      widget.onSignOut();
      
      // Firebase Auth状態変化を確実に反映させるため短い遅延を追加
      await Future.delayed(const Duration(milliseconds: 500));
      print('✅ サインアウト処理が完了しました');

    } catch (error) {
      print('❌ エラーが発生しました: $error');
      print('❌ エラーの型: ${error.runtimeType}');
      
      // ローディングダイアログを確実に閉じる
      if (dialogContext != null && dialogContext!.mounted) {
        print('❌ エラー時: ローディングダイアログを閉じます（保存されたコンテキスト使用）');
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      } else if (context.mounted) {
        print('❌ エラー時: ローディングダイアログを閉じます（元のコンテキスト使用）');
        Navigator.of(context).pop();
      }

      // エラーメッセージを表示
      if (context.mounted) {
        print('💬 エラーメッセージを表示します');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('アカウント削除に失敗しました: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}