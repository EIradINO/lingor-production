import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/word_detail_page.dart';

class MyDictionaryWidget extends StatelessWidget {
  final User user;

  const MyDictionaryWidget({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My辞書'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_words')
            .where('user_id', isEqualTo: user.uid)
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

          final words = snapshot.data?.docs ?? [];

          if (words.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '保存した単語がありません',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '単語学習で単語を保存してみましょう',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadAndSortWords(words),
            builder: (context, wordListSnapshot) {
              if (!wordListSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final sortedWords = wordListSnapshot.data!;

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                itemCount: sortedWords.length + 1,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.grey[200],
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (context, index) {
                  if (index < sortedWords.length) {
                    final wordData = sortedWords[index];
                    return _buildWordListItem(context, wordData);
                  } else {
                    // 一番下の余白
                    return const SizedBox(height: 80);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAndSortWords(List<QueryDocumentSnapshot> words) async {
    List<Map<String, dynamic>> wordList = [];
    
    for (var wordDoc in words) {
      final wordData = wordDoc.data() as Map<String, dynamic>;
      try {
        final dictionaryDoc = await FirebaseFirestore.instance
            .collection('dictionary')
            .doc(wordData['word_id'])
            .get();
        
        if (dictionaryDoc.exists) {
          final dictionaryData = dictionaryDoc.data() as Map<String, dynamic>;
          final word = dictionaryData['original_word'] ?? dictionaryData['word'] ?? '';
          
          // list_idを配列として取得（後方互換性も考慮）
          final dynamic rawListId = wordData['list_id'];
          final List<String> listIds = [];
          if (rawListId is List) {
            listIds.addAll(rawListId.map((id) => id.toString()));
          } else if (rawListId is String) {
            listIds.add(rawListId);
          }
          
          wordList.add({
            'docId': wordDoc.id,
            'word': word,
            'wordId': wordData['word_id'],
            'listIds': listIds,
            'dictionaryData': dictionaryData,
            'examples': wordData['examples'],
            'meanings': wordData['meanings'], // user_wordsのmeaningsも保持
          });
        }
      } catch (e) {
        print('単語の読み込みに失敗: $e');
      }
    }
    
    // アルファベット順にソート
    wordList.sort((a, b) => (a['word'] as String).toLowerCase().compareTo((b['word'] as String).toLowerCase()));
    
    return wordList;
  }

  Widget _buildWordListItem(BuildContext context, Map<String, dynamic> wordData) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        wordData['word'],
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
        final Map<String, dynamic> dictionaryData = (wordData['dictionaryData'] as Map<String, dynamic>);
        final String originalWord = dictionaryData['original_word'] ?? dictionaryData['word'] ?? '';
        final String baseWord = dictionaryData['base_word'] ?? dictionaryData['word'] ?? '';
        final List<String> listIds = wordData['listIds'] as List<String>;

        // user_wordsのmeaningsを使用、なければdictionaryのmeaningsを使用
        final dynamic userMeanings = wordData['meanings'];
        final int numMeanings = (userMeanings is List) 
            ? userMeanings.length 
            : (dictionaryData['meanings'] is List) 
                ? (dictionaryData['meanings'] as List).length 
                : 0;

        // user_words のフラット examples を meaningIndex でネスト再構成
        final dynamic rawExamples = wordData['examples'];
        List<List<Map<String, dynamic>>> nestedExamples = <List<Map<String, dynamic>>>[];
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

        // listIdsから最初の要素を使用
        final String? listIdToPass = listIds.isNotEmpty ? listIds.first : null;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WordDetailPage(
              dictionaryId: wordData['wordId'],
              analysisData: analysisData,
              listId: listIdToPass,
            ),
          ),
        );
      },
    );
  }
}

