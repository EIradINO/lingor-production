import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../pages/conversation_page.dart';

class RoomsTab extends StatelessWidget {
  final String documentId;
  final Future<void> Function(BuildContext)? onReturnFromConversation;
  const RoomsTab({
    super.key,
    required this.documentId,
    this.onReturnFromConversation,
  });

  Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ensureSignedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const Center(child: Text('ユーザー認証に失敗しました'));
        }
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('user_rooms')
              .where('document_id', isEqualTo: documentId)
              .where('user_id', isEqualTo: user.uid)
              .orderBy('created_at', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('エラー: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('質問はまだありません'));
            }
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (context, i) => const Divider(),
              itemBuilder: (context, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final roomId = docs[i].id;
                final title = data['title'] ?? '無題ルーム';
                return ListTile(
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ConversationPage(
                          roomId: roomId,
                          title: title,
                        ),
                      ),
                    );
                    
                    // ConversationPageから直接戻ってきた時（result == true）に親に通知
                    if (result == true && onReturnFromConversation != null) {
                      await onReturnFromConversation!(context);
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}


