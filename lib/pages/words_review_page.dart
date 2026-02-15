import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WordsReviewPage extends StatefulWidget {
  final User user;
  final String? documentId; // 特定のドキュメントに絞り込む場合
  final String? listId; // 特定のリストIDに絞り込む場合

  const WordsReviewPage({
    super.key,
    required this.user,
    this.documentId,
    this.listId,
  });

  @override
  State<WordsReviewPage> createState() => _WordsReviewPageState();
}

class _WordsReviewPageState extends State<WordsReviewPage> {
  List<QueryDocumentSnapshot> userWords = [];
  int currentIndex = 0;
  bool isLoading = false;
  bool showMeaning = false;
  bool isAnswering = false; // 答え処理中かどうか
  Map<String, dynamic>? currentDictionaryData;

  @override
  void initState() {
    super.initState();
    _loadUserWords();
  }

  Future<void> _loadUserWords() async {
    setState(() {
      isLoading = true;
    });

    try {
      List<String> listIds;

      // listIdが指定されている場合は直接それを使用
      if (widget.listId != null) {
        listIds = [widget.listId!];
      } else {
        // user_wordlistsを取得
        final wordlistQuery = widget.documentId != null
            ? FirebaseFirestore.instance
                .collection('user_wordlists')
                .where('user_id', isEqualTo: widget.user.uid)
                .where('document_id', isEqualTo: widget.documentId)
            : FirebaseFirestore.instance
                .collection('user_wordlists')
                .where('user_id', isEqualTo: widget.user.uid);
        
        final wordlistSnapshot = await wordlistQuery.get();

        if (wordlistSnapshot.docs.isEmpty) {
          setState(() {
            isLoading = false;
          });
          return;
        }

        listIds = wordlistSnapshot.docs.map((doc) => doc.id).toList();
      }

      // user_wordsを取得
      final userWordsSnapshot = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: widget.user.uid)
          .get();

      // list_idがwordlistsに含まれているuser_wordsのみをフィルタリング
      final filteredUserWords = userWordsSnapshot.docs.where((userWord) {
        final userWordData = userWord.data();
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

      // シャッフル
      filteredUserWords.shuffle();

      setState(() {
        userWords = filteredUserWords;
        isLoading = false;
      });

      if (userWords.isNotEmpty) {
        _loadCurrentWordData();
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      _showMessage('単語の読み込みに失敗しました: $e');
    }
  }

  Future<void> _loadCurrentWordData() async {
    if (currentIndex >= userWords.length) return;

    final userWordData = userWords[currentIndex].data() as Map<String, dynamic>;
    final wordId = userWordData['word_id'] as String?;

    if (wordId == null) return;

    try {
      final dictionaryDoc = await FirebaseFirestore.instance
          .collection('dictionary')
          .doc(wordId)
          .get();

      if (dictionaryDoc.exists) {
        final dictionaryData = dictionaryDoc.data() as Map<String, dynamic>;
        
        // user_wordsにmeaningsフィールドがあればそれを使用、なければ辞書のmeaningsを使用
        final Map<String, dynamic> combinedData = Map.from(dictionaryData);
        if (userWordData.containsKey('meanings') && userWordData['meanings'] != null) {
          combinedData['meanings'] = userWordData['meanings'];
        }
        
        setState(() {
          currentDictionaryData = combinedData;
          showMeaning = false;
        });
      }
    } catch (e) {
      _showMessage('辞書データの取得に失敗しました: $e');
    }
  }

  Future<void> _recordAnswer(bool isCorrect) async {
    if (currentIndex >= userWords.length || isAnswering) return;

    setState(() {
      isAnswering = true;
    });

    final userWordId = userWords[currentIndex].id;

    try {
      
      final userWordRef = FirebaseFirestore.instance
          .collection('user_words')
          .doc(userWordId);

      // 現在のドキュメントを取得してisCorrectDataフィールドの存在を確認
      final userWordDoc = await userWordRef.get();
      final userData = userWordDoc.data();
      
      if (userData == null) {
        _showMessage('ユーザー単語データが見つかりません');
        return;
      }

      

      // isCorrectDataフィールドが存在しない場合は初期化
      if (!userData.containsKey('isCorrectData')) {
        
        await userWordRef.update({
          'isCorrectData': [],
        });
      }

      // 正誤データを追加
      final newEntry = {
        'isCorrect': isCorrect,
        'timestamp': DateTime.now(),
      };
      
      
      await userWordRef.update({
        'isCorrectData': FieldValue.arrayUnion([newEntry]),
      });

      // isCorrectDataが3つ以上になったらstageをreadingに更新
      final updatedUserWordDoc = await userWordRef.get();
      final updatedUserData = updatedUserWordDoc.data();
      
      if (updatedUserData != null && updatedUserData.containsKey('isCorrectData')) {
        final isCorrectDataList = updatedUserData['isCorrectData'] as List<dynamic>?;
        if (isCorrectDataList != null && isCorrectDataList.length >= 3) {
          await userWordRef.update({
            'stage': 'reading',
          });
        }
      }

      
      _nextCard();
    } catch (e) {
      
      _showMessage('データの保存に失敗しました: $e');
      // エラーが発生してもnextCardを呼んで進む
      _nextCard();
    } finally {
      setState(() {
        isAnswering = false;
      });
    }
  }

  void _nextCard() {
    if (currentIndex < userWords.length - 1) {
      setState(() {
        currentIndex++;
      });
      _loadCurrentWordData();
    } else {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('復習完了！'),
        content: Text('${userWords.length}個の単語の復習が完了しました。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // ダイアログを閉じる
              Navigator.of(context).pop(); // レビューページを閉じる
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.grey),
        ),
      );
    }

    if (userWords.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            '復習する単語がありません',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
            ),
          ),
        ),
      );
    }

    if (currentDictionaryData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.grey),
        ),
      );
    }

    final String word = currentDictionaryData!['original_word'] ?? 
                       currentDictionaryData!['base_word'] ?? 
                       currentDictionaryData!['word'] ?? '';
    
    final List meanings = currentDictionaryData!['meanings'] ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // プログレスバー
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.black),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (currentIndex + 1) / userWords.length,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${currentIndex + 1}/${userWords.length}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // 単語カード
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      showMeaning = !showMeaning;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!showMeaning) ...[
                            Text(
                              word,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'タップして意味を見る',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ] else ...[
                            Text(
                              word,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 30),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: meanings.map<Widget>((meaning) {
                                    String definition = '';
                                    String partOfSpeech = '';
                                    
                                    if (meaning is Map<String, dynamic>) {
                                      // Map形式の場合
                                      definition = meaning['definition'] as String? ?? '';
                                      partOfSpeech = meaning['part_of_speech'] as String? ?? '';
                                    } else if (meaning is String) {
                                      // 文字列形式の場合
                                      definition = meaning;
                                    }
                                    
                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (partOfSpeech.isNotEmpty) ...[
                                            Text(
                                              partOfSpeech,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          Text(
                                            definition,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 16,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 答えボタン（意味が表示されている時のみ）
              if (showMeaning) ...[
                if (isAnswering) ...[
                  const Center(
                    child: CircularProgressIndicator(color: Colors.grey),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // バツボタン
                      GestureDetector(
                        onTap: () => _recordAnswer(false),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      
                      // マルボタン
                      GestureDetector(
                        onTap: () => _recordAnswer(true),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  isAnswering 
                    ? '記録中...' 
                    : '知っていたら ✓、知らなかったら ✗',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
} 