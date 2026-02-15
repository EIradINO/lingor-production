import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({super.key});

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _screenController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // デフォルト値を設定
    _titleController.text = 'テスト通知';
    _bodyController.text = 'LingoSavorからのテスト通知です！';
    _screenController.text = 'home';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _screenController.dispose();
    super.dispose();
  }

  /// Firebase Functionsを使って通知を送信
  Future<void> _sendNotificationViaFunction() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('ログインが必要です', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      HttpsCallable callable = FirebaseFunctions.instance
          .httpsCallable('sendNotificationManual');
      
      final result = await callable.call({
        'userId': user.uid,
        'title': _titleController.text,
        'body': _bodyController.text,
        'screen': _screenController.text.isNotEmpty ? _screenController.text : null,
        'additionalData': {
          'testData': 'test_value',
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      if (result.data['success'] == true) {
        _showSnackBar(
          '通知を送信しました！ID: ${result.data['notificationId']}',
          Colors.green,
        );
      } else {
        _showSnackBar('通知の送信に失敗しました', Colors.red);
      }
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Firestoreに直接書き込んで通知をトリガー
  Future<void> _sendNotificationViaFirestore() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('ログインが必要です', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final notificationRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc();

      await notificationRef.set({
        'userId': user.uid,
        'title': _titleController.text,
        'body': _bodyController.text,
        'screen': _screenController.text.isNotEmpty ? _screenController.text : null,
        'data': {
          'testData': 'direct_firestore',
          'timestamp': DateTime.now().toIso8601String(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'status': 'pending',
      });

      _showSnackBar(
        '通知を送信しました！ID: ${notificationRef.id}',
        Colors.green,
      );
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// FCMトークンを再取得
  Future<void> _refreshFCMToken() async {
    setState(() => _isLoading = true);

    try {
      await NotificationService().refreshToken();
      _showSnackBar('FCMトークンを更新しました', Colors.blue);
    } catch (e) {
      _showSnackBar('トークン更新エラー: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 現在のFCMトークンを表示
  Future<void> _showCurrentToken() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('ログインが必要です', Colors.red);
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final fcmToken = userDoc.data()?['fcmToken'];
        if (fcmToken != null) {
          _showDialog('現在のFCMトークン', fcmToken);
        } else {
          _showSnackBar('FCMトークンが見つかりません', Colors.orange);
        }
      } else {
        _showSnackBar('ユーザードキュメントが見つかりません', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知テスト'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 通知内容の入力フィールド
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '通知内容',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'タイトル',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyController,
                      decoration: const InputDecoration(
                        labelText: '本文',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _screenController,
                      decoration: const InputDecoration(
                        labelText: '遷移先画面 (オプション)',
                        border: OutlineInputBorder(),
                        hintText: 'home, word_detail, conversation など',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 通知送信ボタン
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '通知送信',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _sendNotificationViaFunction,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Functions経由で送信'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _sendNotificationViaFirestore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      child: const Text('Firestore直接書き込み'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // デバッグ機能
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'デバッグ機能',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _showCurrentToken,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                            child: const Text('FCMトークン表示'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _refreshFCMToken,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                            ),
                            child: const Text('トークン更新'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // 注意事項
            Card(
              color: Colors.yellow[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        const Text(
                          '注意事項',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• 実機でのテストが必要です（シミュレータでは通知を受信できません）\n'
                      '• フォアグラウンド時とバックグラウンド時で通知の表示方法が異なります\n'
                      '• 通知の許可が必要です（初回起動時に確認されます）',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
