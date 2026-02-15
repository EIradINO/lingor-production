import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/todays_word_card.dart';
import 'conversation_page.dart';

class AiWaitingReviewPage extends StatefulWidget {
  final String roomId;
  final String title;
  final bool fromConversation;

  const AiWaitingReviewPage({
    super.key,
    required this.roomId,
    required this.title,
    this.fromConversation = false,
  });

  @override
  State<AiWaitingReviewPage> createState() => _AiWaitingReviewPageState();
}

class _AiWaitingReviewPageState extends State<AiWaitingReviewPage> {
  // AI応答検知
  bool _aiResponseReceived = false;
  int? _initialModelMessageCount;
  StreamSubscription<QuerySnapshot>? _messageSubscription;

  // 単語復習関連
  Map<String, dynamic>? dailyTasks;
  List<Map<String, dynamic>> wordList = [];
  bool isLoadingWords = true;
  int currentWordIndex = 0;
  bool showWordMeaning = false;

  @override
  void initState() {
    super.initState();
    _listenForAiResponse();
    _loadDailyTasks();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _listenForAiResponse() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _messageSubscription = FirebaseFirestore.instance
        .collection('messages')
        .where('user_id', isEqualTo: user.uid)
        .where('room_id', isEqualTo: widget.roomId)
        .orderBy('created_at')
        .snapshots()
        .listen((snapshot) {
      final modelMessages =
          snapshot.docs.where((doc) {
            final data = doc.data();
            return data['role'] == 'model';
          }).length;

      if (_initialModelMessageCount == null) {
        _initialModelMessageCount = modelMessages;
        return;
      }

      if (modelMessages > _initialModelMessageCount! && mounted) {
        setState(() {
          _aiResponseReceived = true;
        });
      }
    });
  }

  Future<void> _loadDailyTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => isLoadingWords = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('user_tasks')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            dailyTasks = snapshot.docs.first.data();
            dailyTasks!['id'] = snapshot.docs.first.id;
          });
          _loadWordList();
        }
      } else {
        if (mounted) {
          setState(() {
            dailyTasks = null;
            isLoadingWords = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingWords = false);
    }
  }

  void _loadWordList() {
    if (dailyTasks == null) {
      setState(() => isLoadingWords = false);
      return;
    }

    try {
      final wordListData = dailyTasks!['word_list'] as List<dynamic>?;
      if (wordListData != null) {
        setState(() {
          wordList =
              wordListData.map((e) => Map<String, dynamic>.from(e)).toList();
          currentWordIndex = 0;
          showWordMeaning = false;
          isLoadingWords = false;
        });
      } else {
        setState(() => isLoadingWords = false);
      }
    } catch (e) {
      setState(() => isLoadingWords = false);
    }
  }

  Future<void> _recordWordAnswer(String wordId, bool isCorrect) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userWordsQuery = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: user.uid)
          .where('word_id', isEqualTo: wordId)
          .limit(1)
          .get();

      if (userWordsQuery.docs.isNotEmpty) {
        final userWordRef = userWordsQuery.docs.first.reference;
        final userData = userWordsQuery.docs.first.data();

        if (!userData.containsKey('isCorrectData')) {
          await userWordRef.update({
            'isCorrectData': [],
          });
        }

        final newEntry = {
          'isCorrect': isCorrect,
          'timestamp': DateTime.now(),
        };

        await userWordRef.update({
          'isCorrectData': FieldValue.arrayUnion([newEntry]),
        });

        final updatedDoc = await userWordRef.get();
        final updatedData = updatedDoc.data();

        if (updatedData != null && updatedData.containsKey('isCorrectData')) {
          final isCorrectDataList =
              updatedData['isCorrectData'] as List<dynamic>?;
          if (isCorrectDataList != null && isCorrectDataList.length >= 3) {
            await userWordRef.update({
              'stage': 'reading',
            });
          }
        }
      }
    } catch (e) {
      print('Word answer recording error: $e');
    }
  }

  void _nextWord() {
    setState(() {
      showWordMeaning = false;
      if (currentWordIndex < wordList.length - 1) {
        currentWordIndex++;
      } else {
        _updateTaskCompleted('word', true);
      }
    });
  }

  Future<void> _updateTaskCompleted(String taskType, bool completed) async {
    if (dailyTasks == null) return;

    try {
      final List<dynamic> isCompletedList =
          List.from(dailyTasks!['isCompleted'] ?? []);

      if (completed && !isCompletedList.contains(taskType)) {
        isCompletedList.add(taskType);
      } else if (!completed) {
        isCompletedList.remove(taskType);
      }

      await FirebaseFirestore.instance
          .collection('user_tasks')
          .doc(dailyTasks!['id'])
          .update({
        'isCompleted': isCompletedList,
      });

      if (mounted) {
        setState(() {
          dailyTasks!['isCompleted'] = isCompletedList;
        });
      }
    } catch (e) {
      print('Update completed error: $e');
    }
  }

  void _navigateToConversation() {
    if (widget.fromConversation) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationPage(
            roomId: widget.roomId,
            title: widget.title,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: AppBar(
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, color: Colors.black),
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
      ),
      body: Column(
        children: [
          // AI応答ステータスインジケーター
          _buildAiStatusIndicator(),
          // メインコンテンツ
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildAiStatusIndicator() {
    return GestureDetector(
      onTap: _aiResponseReceived ? _navigateToConversation : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: _aiResponseReceived ? Colors.green.shade50 : Colors.blue.shade50,
          border: Border(
            bottom: BorderSide(
              color: _aiResponseReceived ? Colors.green.shade200 : Colors.blue.shade200,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _aiResponseReceived
              ? [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'AIの回答が届きました！',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios, color: Colors.green.shade600, size: 16),
                ]
              : [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'AIが回答を作成中...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (isLoadingWords) {
      return const Center(child: CircularProgressIndicator());
    }

    if (wordList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '復習する単語はありません',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AIの回答をお待ちください',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    final List<dynamic> isCompletedList = dailyTasks?['isCompleted'] ?? [];
    final bool isCompleted = isCompletedList.contains('word');
    final Map<String, dynamic> wordData = wordList[currentWordIndex];
    final String word = wordData['word'] ?? '';
    final List<String> meanings =
        (wordData['meaning'] as List<dynamic>? ?? const []).cast<String>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: TodaysWordCard(
        isCompleted: isCompleted,
        word: word,
        meanings: meanings,
        currentIndex: currentWordIndex + 1,
        total: wordList.length,
        showMeaning: showWordMeaning,
        onToggleMeaning: () {
          setState(() {
            showWordMeaning = !showWordMeaning;
          });
        },
        onAnswer: (bool isCorrect) {
          _recordWordAnswer(wordData['id'], isCorrect);
          _nextWord();
        },
      ),
    );
  }
}
