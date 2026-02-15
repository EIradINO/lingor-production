import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/word_detail_page.dart';
import '../pages/words_review_page.dart';

class SavedWordsTab extends StatefulWidget {
  final User user;
  final String? documentId; // 特定のドキュメントに絞り込む場合

  const SavedWordsTab({
    super.key,
    required this.user,
    this.documentId,
  });

  @override
  State<SavedWordsTab> createState() => _SavedWordsTabState();
}

class _SavedWordsTabState extends State<SavedWordsTab> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 復習ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => WordsReviewPage(
                      user: widget.user,
                      documentId: widget.documentId,
                    ),
                  ),
                );
              },
              label: const Text('復習'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.documentId != null
                ? FirebaseFirestore.instance
                    .collection('user_wordlists')
                    .where('user_id', isEqualTo: widget.user.uid)
                    .where('document_id', isEqualTo: widget.documentId)
                    .snapshots()
                : FirebaseFirestore.instance
                    .collection('user_wordlists')
                    .where('user_id', isEqualTo: widget.user.uid)
                    .snapshots(),
              builder: (context, wordlistSnapshot) {
                if (wordlistSnapshot.hasError) {
                  return Center(
                    child: Text('エラー: ${wordlistSnapshot.error}'),
                  );
                }
                
                if (wordlistSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                
                final wordlists = wordlistSnapshot.data?.docs ?? [];
                
                if (wordlists.isEmpty) {
                  return const Center(
                    child: Text(
                      '単語リストがありません',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }
                
                // wordlistのIDリストを作成
                final List<String> listIds = wordlists.map((doc) => doc.id).toList();
                
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('user_words')
                      .where('user_id', isEqualTo: widget.user.uid)
                      .orderBy('created_at', descending: true)
                      .snapshots(),
                  builder: (context, wordsSnapshot) {
                    if (wordsSnapshot.hasError) {
                      return Center(
                        child: Text('エラー: ${wordsSnapshot.error}'),
                      );
                    }
                    
                    if (wordsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    
                    final allUserWords = wordsSnapshot.data?.docs ?? [];
                    
                    // list_idがwordlistsに含まれているuser_wordsのみをフィルタリング
                    final userWords = allUserWords.where((userWord) {
                      final userWordData = userWord.data() as Map<String, dynamic>;
                      final userWordListIds = userWordData['list_id'];
                      
                      // list_idが配列の場合
                      if (userWordListIds is List) {
                        return userWordListIds.any((id) => listIds.contains(id.toString()));
                      }
                      // list_idが文字列の場合（後方互換性）
                      if (userWordListIds is String) {
                        return listIds.contains(userWordListIds);
                      }
                      return false;
                    }).toList();
                    
                    if (userWords.isEmpty) {
                      return const Center(
                        child: Text(
                          '保存された単語はありません',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }
                    
                    return ListView.separated(
                      itemCount: userWords.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final userWord = userWords[index];
                        final userWordData = userWord.data() as Map<String, dynamic>;
                        final wordId = userWordData['word_id'] as String?;
                        
                        // list_idを配列として取得（後方互換性も考慮）
                        final dynamic rawListId = userWordData['list_id'];
                        final List<String> userWordListIds = [];
                        if (rawListId is List) {
                          userWordListIds.addAll(rawListId.map((id) => id.toString()));
                        } else if (rawListId is String) {
                          userWordListIds.add(rawListId);
                        }
                        
                        if (wordId == null) {
                          return const ListTile(
                            title: Text('データエラー'),
                            subtitle: Text('word_idが見つかりません'),
                          );
                        }
                        
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('dictionary')
                              .doc(wordId)
                              .get(),
                          builder: (context, dictionarySnapshot) {
                            if (dictionarySnapshot.hasError) {
                              return ListTile(
                                title: const Text('単語データエラー'),
                                subtitle: Text('辞書データの取得に失敗: ${dictionarySnapshot.error}'),
                              );
                            }
                            
                            if (dictionarySnapshot.connectionState == ConnectionState.waiting) {
                              return const ListTile(
                                title: Text('読み込み中...'),
                                leading: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            }
                            
                            if (!dictionarySnapshot.hasData || !dictionarySnapshot.data!.exists) {
                              return const ListTile(
                                title: Text('単語が見つかりません'),
                                subtitle: Text('辞書データが削除されている可能性があります'),
                              );
                            }
                            
                            final dictionaryData = dictionarySnapshot.data!.data() as Map<String, dynamic>;
                            final originalWord = dictionaryData['original_word'] as String? ?? 
                                               dictionaryData['word'] as String? ?? '不明な単語';
                            final baseWord = dictionaryData['base_word'] as String? ?? 
                                            dictionaryData['word'] as String? ?? '';
                            // 品詞は表示しないため未使用
                            final pronunciation = dictionaryData['pronunciation'] as String? ?? '';
                            // meanings の全定義とそれぞれの品詞を取得（user_wordsのmeaningsを優先）
                            final dynamic rawMeanings = userWordData['meanings'] ?? dictionaryData['meanings'];
                            final List<Map<String, dynamic>> meaningItems = <Map<String, dynamic>>[];
                            if (rawMeanings is List) {
                              for (final dynamic m in rawMeanings) {
                                if (m is Map<String, dynamic>) {
                                  // Map形式の場合
                                  meaningItems.add({
                                    'definition': m['definition'] as String? ?? '',
                                    'part_of_speech': m['part_of_speech'] as String? ?? '',
                                  });
                                } else if (m is String) {
                                  // 文字列形式の場合
                                  meaningItems.add({
                                    'definition': m,
                                    'part_of_speech': '',
                                  });
                                }
                              }
                            }
                            
                            return ListTile(
                              title: Text(
                                originalWord,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (baseWord.isNotEmpty && baseWord != originalWord)
                                    Text(
                                      '原形: $baseWord',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[600],
                                      ),
                                    ),
                                  if (pronunciation.isNotEmpty)
                                    Text(
                                      pronunciation,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  if (meaningItems.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    ...meaningItems.asMap().entries.map((entry) {
                                      final int meaningIndex = entry.key + 1;
                                      final Map<String, dynamic> meaning = entry.value;
                                      final String meaningDefinition = meaning['definition'] as String? ?? '';
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 番号
                                            Text(
                                              '$meaningIndex.',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // 定義
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    meaningDefinition,
                                                    style: const TextStyle(
                                                      fontSize: 15, // 少し大きめ
                                                      color: Colors.black87,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                // user_words に保存された examples（フラット）をネストに再構成
                                final dynamic rawExamples = userWordData['examples'];
                                List<List<Map<String, dynamic>>> nestedExamples = <List<Map<String, dynamic>>>[];
                                final int numMeanings = meaningItems.length;
                                if (numMeanings > 0) {
                                  nestedExamples = List.generate(numMeanings, (_) => <Map<String, dynamic>>[]);
                                }
                                if (rawExamples is List) {
                                  for (final dynamic e in rawExamples) {
                                    if (e is Map) {
                                      final Map<String, dynamic> ex = Map<String, dynamic>.from(e);
                                      final int? meaningIndex = ex['meaningIndex'] is int ? ex['meaningIndex'] as int : null;
                                      final String? original = ex['original'] as String?;
                                      final String? translation = ex['translation'] as String?;
                                      if (meaningIndex != null &&
                                          meaningIndex >= 0 &&
                                          meaningIndex < (nestedExamples.isEmpty ? 0 : nestedExamples.length) &&
                                          original != null &&
                                          translation != null) {
                                        nestedExamples[meaningIndex].add({
                                          'original': original,
                                          'translation': translation,
                                        });
                                      }
                                    }
                                  }
                                }

                                final Map<String, dynamic> analysisData = {
                                  'original_word': originalWord,
                                  'base_word': baseWord,
                                  'examples': nestedExamples,
                                };

                                // 現在のdocumentIdに対応するlistIdを探す
                                String? listIdToPass;
                                if (widget.documentId != null && userWordListIds.isNotEmpty) {
                                  // documentIdに対応するuser_wordlistを探す
                                  for (final listId in userWordListIds) {
                                    if (listIds.contains(listId)) {
                                      listIdToPass = listId;
                                      break;
                                    }
                                  }
                                }
                                // 見つからない場合は最初のlistIdを使用
                                listIdToPass ??= userWordListIds.isNotEmpty ? userWordListIds.first : null;

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => WordDetailPage(
                                      dictionaryId: wordId,
                                      analysisData: analysisData,
                                      listId: listIdToPass,
                                      documentId: widget.documentId,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
} 