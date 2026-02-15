import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/wordlist_detail_page.dart';
import '../pages/wordlist_edit_page.dart';

class MyWordlistsWidget extends StatelessWidget {
  final User user;

  const MyWordlistsWidget({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My単語帳'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // 現在の日時でタイトルを作成
          final now = DateTime.now();
          final title = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          
          // 新しいwordlistを作成
          final newWordlist = await FirebaseFirestore.instance
              .collection('user_wordlists')
              .add({
            'user_id': user.uid,
            'title': title,
            'created_at': FieldValue.serverTimestamp(),
            'word_order': [], // 単語の順番を保存する配列
          });
          
          // 編集ページへ遷移
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => WordlistEditPage(
                  user: user,
                  listId: newWordlist.id,
                  initialTitle: title,
                ),
              ),
            );
          }
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_wordlists')
            .where('user_id', isEqualTo: user.uid)
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('エラーが発生しました: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final wordlists = snapshot.data?.docs ?? [];

          if (wordlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '単語帳がありません',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ドキュメントから単語を保存してみましょう',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            itemCount: wordlists.length + 1,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey[200],
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (context, index) {
              if (index < wordlists.length) {
                final wordlistDoc = wordlists[index];
                final wordlistData = wordlistDoc.data() as Map<String, dynamic>;
                final title = wordlistData['title'] ?? '無題の単語帳';
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
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
                        builder: (context) => WordlistDetailPage(
                          user: user,
                          listId: wordlistDoc.id,
                          title: title,
                        ),
                      ),
                    );
                  },
                );
              } else {
                // 一番下の余白
                return const SizedBox(height: 80);
              }
            },
          );
        },
      ),
    );
  }
}

