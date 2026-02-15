import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/gem_purchase_widget.dart';
import '../widgets/todays_word_card.dart';
import '../widgets/grammar_task_widget.dart';
import '../widgets/reading_listening_task_widget.dart';
import '../widgets/adfree_purchase_card.dart';

class HomePage extends StatefulWidget {
  final User user;

  const HomePage({
    super.key,
    required this.user,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? dailyTasks;
  bool isLoading = true;
  
  // 単語帳関連
  List<Map<String, dynamic>> wordList = [];
  bool isLoadingWords = false;
  int currentWordIndex = 0;
  bool showWordMeaning = false;
  
  // ユーザープラン関連
  String userPlan = 'free';
  bool removeAds = false;
  bool isLoadingUserData = true;
  
  // チュートリアル用のGlobalKey
  final GlobalKey _reviewTasksKey = GlobalKey();
  
  // ShowCaseWidget内のBuildContextを保存
  BuildContext? _showcaseContext;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDailyTasks();
  }
  
  // チュートリアルを表示するかチェック
  Future<void> _checkAndShowTutorial() async {
    // user_tasksがない場合は表示しない
    if (dailyTasks == null) return;
    
    // showcaseContextがない場合は表示しない
    if (_showcaseContext == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial = prefs.getBool('home_page_tutorial_shown') ?? false;
    
    if (!hasShownTutorial && mounted) {
      // 今日の単語と復習問題全体を1つのハイライトで表示
      ShowCaseWidget.of(_showcaseContext!).startShowCase([_reviewTasksKey]);
      // フラグを保存
      await prefs.setBool('home_page_tutorial_shown', true);
    }
  }


  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            userPlan = data['plan'] ?? 'free';
            removeAds = data['remove_ads'] ?? false;
            isLoadingUserData = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            userPlan = 'free';
            removeAds = false;
            isLoadingUserData = false;
          });
        }
      }
    } catch (e) {
      print('User data loading error: $e');
      if (mounted) {
        setState(() {
          userPlan = 'free';
          removeAds = false;
          isLoadingUserData = false;
        });
      }
    }
  }

  Future<void> _loadDailyTasks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('user_tasks')
          .where('userId', isEqualTo: widget.user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            dailyTasks = snapshot.docs.first.data();
            dailyTasks!['id'] = snapshot.docs.first.id; // ドキュメントIDを保存
            isLoading = false;
          });
        }
        // データ読み込み完了後に単語リストを読み込み
        if (mounted) {
          _loadWordList();
          // データ読み込み完了後にチュートリアルを表示
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndShowTutorial();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            dailyTasks = null;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Daily tasks loading error: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _updateTaskCompleted(String taskType, bool completed) async {
    if (dailyTasks == null) return;

    try {
      final List<dynamic> isCompletedList = List.from(dailyTasks!['isCompleted'] ?? []);
      
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

  Future<void> _loadWordList() async {
    if (dailyTasks == null) return;
    
    if (mounted) {
      setState(() {
        isLoadingWords = true;
      });
    }

    try {
      final wordListData = dailyTasks!['word_list'] as List<dynamic>?;
      if (wordListData != null) {
        // そのままMap<String, dynamic>のリストとしてセット
        if (mounted) {
          setState(() {
            wordList = wordListData.map((e) => Map<String, dynamic>.from(e)).toList();
            currentWordIndex = 0;
            showWordMeaning = false;
          });
        }
      }
    } catch (e) {
      print('Word list loading error: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingWords = false;
        });
      }
    }
  }

  Future<void> _recordWordAnswer(String wordId, bool isCorrect) async {
    try {
      // user_wordsコレクションを確認
      final userWordsQuery = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: widget.user.uid)
          .where('word_id', isEqualTo: wordId)
          .limit(1)
          .get();

      if (userWordsQuery.docs.isNotEmpty) {
        // 既存のドキュメントを更新
        final userWordRef = userWordsQuery.docs.first.reference;
        final userData = userWordsQuery.docs.first.data();
        
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
        final updatedDoc = await userWordRef.get();
        final updatedData = updatedDoc.data();
        
        if (updatedData != null && updatedData.containsKey('isCorrectData')) {
          final isCorrectDataList = updatedData['isCorrectData'] as List<dynamic>?;
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
        // 最後のカードなので完了処理
        _updateTaskCompleted('word', true);
      }
    });
  }




  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) {
        // ShowCaseWidget内のcontextを保存
        _showcaseContext = context;
        return Scaffold(
          backgroundColor: Colors.grey[50],
          body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 広告なしプランカードとGem追加（freeプランの時のみ表示）
            if (!isLoadingUserData && userPlan == 'free') ...[
              // remove_adsがtrueの場合は広告なしプランカードを表示しない
              if (!removeAds) ...[
                const AdFreePurchaseCard(),
                const SizedBox(height: 16),
              ],
              const GemPurchaseWidget(),
              const SizedBox(height: 16),
            ],
            
            // Word Card Section and Daily Tasks Section (全体を1つのShowcaseで囲む)
            if (isLoading || isLoadingUserData)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isLoadingUserData && wordList.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final List<dynamic> isCompletedList = dailyTasks?['isCompleted'] ?? [];
                        final bool isCompleted = isCompletedList.contains('word');
                        final Map<String, dynamic> wordData = wordList[currentWordIndex];
                        final String word = wordData['word'] ?? '';
                        final List<String> meanings = (wordData['meaning'] as List<dynamic>? ?? const []).cast<String>();
                        return TodaysWordCard(
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
                        );
                      },
                    ),
                  Text(
                    '復習問題',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              )
            else if (dailyTasks == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isLoadingUserData && wordList.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final List<dynamic> isCompletedList = dailyTasks?['isCompleted'] ?? [];
                        final bool isCompleted = isCompletedList.contains('word');
                        final Map<String, dynamic> wordData = wordList[currentWordIndex];
                        final String word = wordData['word'] ?? '';
                        final List<String> meanings = (wordData['meaning'] as List<dynamic>? ?? const []).cast<String>();
                        return TodaysWordCard(
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
                        );
                      },
                    ),
                  Text(
                    '復習問題',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.assignment,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '今日の復習問題は準備中です...',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '分からない単語を保存したり',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '分からない文法を質問して',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'より効果的な復習問題を作ろう！',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Showcase(
                key: _reviewTasksKey,
                title: '復習問題が作成されました！',
                description: '忘れかけている単語リストと復習問題をAIが毎日作成します！毎日復習して理解を深めましょう！',
                targetPadding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 今日の単語カード
                    if (!isLoadingUserData && wordList.isNotEmpty)
                      Builder(
                        builder: (context) {
                          final List<dynamic> isCompletedList = dailyTasks?['isCompleted'] ?? [];
                          final bool isCompleted = isCompletedList.contains('word');
                          final Map<String, dynamic> wordData = wordList[currentWordIndex];
                          final String word = wordData['word'] ?? '';
                          final List<String> meanings = (wordData['meaning'] as List<dynamic>? ?? const []).cast<String>();
                          return TodaysWordCard(
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
                          );
                        },
                      ),
                    // 復習問題タイトル
                    Text(
                      '復習問題',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 各タスク
                    if (dailyTasks!.containsKey('grammar_list') && (dailyTasks!['grammar_list'] as List).isNotEmpty)
                      GrammarTaskWidget(
                        title: '文法問題',
                        grammarList: dailyTasks!['grammar_list'],
                        taskType: 'grammar',
                        isCompletedList: dailyTasks?['isCompleted'] ?? [],
                        taskDocId: dailyTasks!['id'],
                        answers: dailyTasks?['answers']?['grammar'] ?? [],
                        onTaskCompletedUpdate: _updateTaskCompleted,
                      ),
                    if (dailyTasks!.containsKey('reading'))
                      ReadingListeningTaskWidget(
                        title: 'リーディング',
                        task: dailyTasks!['reading'],
                        taskType: 'reading',
                        isCompletedList: dailyTasks?['isCompleted'] ?? [],
                        taskDocId: dailyTasks!['id'],
                        answers: dailyTasks?['answers']?['reading'] ?? [],
                        onTaskCompletedUpdate: _updateTaskCompleted,
                      ),
                    if (dailyTasks!.containsKey('listening'))
                      ReadingListeningTaskWidget(
                        title: 'リスニング',
                        task: dailyTasks!['listening'],
                        taskType: 'listening',
                        isCompletedList: dailyTasks?['isCompleted'] ?? [],
                        taskDocId: dailyTasks!['id'],
                        answers: dailyTasks?['answers']?['listening'] ?? [],
                        onTaskCompletedUpdate: _updateTaskCompleted,
                      ),
                  ],
                ),
              ),
          ],
        ),
        ),
        );
      },
    );
  }





} 