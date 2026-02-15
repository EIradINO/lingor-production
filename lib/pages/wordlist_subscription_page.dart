import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 市販単語帳の登録ページ
/// ユーザーが使用する単語帳を選択し、users/{userId}/subscribed_wordlistsに保存する
class WordlistSubscriptionPage extends StatefulWidget {
  final User user;

  const WordlistSubscriptionPage({
    super.key,
    required this.user,
  });

  @override
  State<WordlistSubscriptionPage> createState() => _WordlistSubscriptionPageState();
}

class _WordlistSubscriptionPageState extends State<WordlistSubscriptionPage> {
  // 利用可能な単語帳リスト（published_wordlistsから取得）
  List<Map<String, dynamic>> _availableWordlists = [];
  // ユーザーが登録済みの単語帳ID
  Set<String> _subscribedWordlistIds = {};
  // ローディング状態
  bool _isLoading = true;
  // 保存中状態
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 利用可能な単語帳一覧を取得
      final wordlistsSnapshot = await FirebaseFirestore.instance
          .collection('published_wordlists')
          .get();

      final wordlists = wordlistsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? '',
          'total_words': data['total_words'] ?? 0,
        };
      }).toList();

      // タイトルでソート
      wordlists.sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));

      // 2. ユーザーの登録済み単語帳を取得
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      final userData = userDoc.data();
      final subscribedList = (userData?['subscribed_wordlists'] as List<dynamic>?) ?? [];
      final subscribedIds = subscribedList.map((e) => e.toString()).toSet();

      setState(() {
        _availableWordlists = wordlists;
        _subscribedWordlistIds = subscribedIds;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading wordlists: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('単語帳の読み込みに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleSubscription(String wordlistId) async {
    setState(() {
      if (_subscribedWordlistIds.contains(wordlistId)) {
        _subscribedWordlistIds.remove(wordlistId);
      } else {
        _subscribedWordlistIds.add(wordlistId);
      }
    });
  }

  Future<void> _saveSubscriptions() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
        'subscribed_wordlists': _subscribedWordlistIds.toList(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('単語帳の登録を保存しました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error saving subscriptions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('市販単語帳の登録'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSubscriptions,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _availableWordlists.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        '利用可能な単語帳がありません',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 説明文
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.blue[50],
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '登録した単語帳に収録されている単語が、教材解析時に表示されます',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 選択数
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text(
                            '${_subscribedWordlistIds.length}冊選択中',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_subscribedWordlistIds.length == _availableWordlists.length) {
                                  _subscribedWordlistIds.clear();
                                } else {
                                  _subscribedWordlistIds = _availableWordlists
                                      .map((w) => w['id'] as String)
                                      .toSet();
                                }
                              });
                            },
                            child: Text(
                              _subscribedWordlistIds.length == _availableWordlists.length
                                  ? '全て解除'
                                  : '全て選択',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 単語帳リスト
                    Expanded(
                      child: ListView.builder(
                        itemCount: _availableWordlists.length,
                        itemBuilder: (context, index) {
                          final wordlist = _availableWordlists[index];
                          final id = wordlist['id'] as String;
                          final title = wordlist['title'] as String;
                          final totalWords = wordlist['total_words'] as int;
                          final isSubscribed = _subscribedWordlistIds.contains(id);

                          return _buildWordlistTile(
                            id: id,
                            title: title,
                            totalWords: totalWords,
                            isSubscribed: isSubscribed,
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildWordlistTile({
    required String id,
    required String title,
    required int totalWords,
    required bool isSubscribed,
  }) {
    return InkWell(
      onTap: () => _toggleSubscription(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            // チェックボックス
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSubscribed
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSubscribed
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: isSubscribed
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 16),
            // 単語帳アイコン
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.menu_book,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            // 単語帳情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalWords語収録',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
