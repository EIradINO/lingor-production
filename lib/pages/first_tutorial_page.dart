import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

class FirstTutorialPage extends StatefulWidget {
  const FirstTutorialPage({super.key});

  @override
  State<FirstTutorialPage> createState() => _FirstTutorialPageState();
}

class _FirstTutorialPageState extends State<FirstTutorialPage> with TickerProviderStateMixin {
  int _currentMessageIndex = 0;
  bool _showGoalSelection = false;
  int _currentPhase = 0; // 0: 初期, 1: 目標選択後, 2: 最終メッセージ
  final List<String> _messages = [
    'こんにちは👋、LingoSavor(リンゴセーバー)へようこそ！\nダウンロードしてくれてありがとう😊💞',
    'このアプリを入れてくれたということは\n受験や英検、TOEICや資格試験などを目指して\n日々英語学習を頑張っているのだと思います🔥',
    'あなたの目標を教えてください！',
  ];
  
  final List<String> _afterGoalMessages = [
    '世の中は様々な英語アプリで溢れています😵',
    'ですが、そのほとんどが英単語アプリか英会話アプリのどちらかです',
    'そんな中で、LingoSavorはリーディングとリスニングの\n「復習」に特化した学習コンテンツを提供する、唯一無二のアプリです🎉',
  ];
  
  final List<String> _finalMessages = [
    'せっかくたくさんの英文を読んだり聴いたりしても、復習しなければ英語力は向上しません',
    '分からなかった単語を辞書で調べて',
    '単語帳にまとめて',
    '分からなかった文法を検索したり人に訊いたりして理解して',
    '一文ずつ翻訳して',
    '音読もして......',
    '正直めちゃくちゃ面倒くさいし、その労力に見合う効果があるのか不安ですよね......',
    'LingoSavorなら、これらの作業にかかる時間を半分に、復習効果を２倍にすることができます！',
    'どうやって？\nそろそろこのチャットにも飽きてきた頃でしょうから、実際にお見せしましょう！',
    'まずはアカウントを作成してください',
  ];
  
  final List<String> _goalOptions = [
    '大学受験合格',
    '高校受験合格', 
    '英検',
    'TOEIC',
    'TOEFL・IELTS',
    '学校の授業の理解',
    'その他',
  ];
  
  late List<AnimationController> _animationControllers;
  late List<Animation<Offset>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    // 最初のメッセージを表示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNextMessage();
    });
  }

  void _initializeAnimations() {
    _animationControllers = List.generate(
      _messages.length + _afterGoalMessages.length + _finalMessages.length,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );

    _slideAnimations = _animationControllers.map((controller) {
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
      ));
    }).toList();

    _fadeAnimations = _animationControllers.map((controller) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ));
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showNextMessage() {
    if (_currentPhase == 0) {
      // 初期メッセージフロー
      if (_currentMessageIndex < _messages.length) {
        _animationControllers[_currentMessageIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else if (!_showGoalSelection) {
        // 最後のメッセージの後のタップで選択肢を表示
        setState(() {
          _showGoalSelection = true;
        });
      }
    } else if (_currentPhase == 1) {
      // 目標選択後のメッセージフロー
      if (_currentMessageIndex < _afterGoalMessages.length) {
        _animationControllers[_currentMessageIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else {
        // 第2フェーズ終了、チャットをリセットして最終メッセージへ
        _resetChatForFinalPhase();
      }
    } else if (_currentPhase == 2) {
      // 最終メッセージフロー
      if (_currentMessageIndex < _finalMessages.length) {
        _animationControllers[_currentMessageIndex].forward();
        setState(() {
          _currentMessageIndex++;
        });
      } else {
        // 全てのメッセージが表示された後は、チュートリアル完了を保存してログインページに遷移
        _completeTutorial();
      }
    }
  }
  
  void _resetChatForFinalPhase() {
    setState(() {
      _currentPhase = 2;
      _currentMessageIndex = 0;
    });
    
    // アニメーションコントローラーをリセット
    for (var controller in _animationControllers) {
      controller.reset();
    }
    
    // 少し間を置いてから最終メッセージを開始
    Future.delayed(const Duration(milliseconds: 500), () {
      _showNextMessage();
    });
  }
  
  Future<void> _selectGoal(String goal) async {
    // shared_preferencesに目標を保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_goal', goal);
    
    // チャットを完全にリセットして第2フェーズへ
    setState(() {
      _showGoalSelection = false;
      _currentPhase = 1;
      _currentMessageIndex = 0; // メッセージインデックスをリセット
    });
    
    // アニメーションコントローラーもリセット
    for (var controller in _animationControllers) {
      controller.reset();
    }
    
    // 選択後、少し間を置いてから次のメッセージを開始
    await Future.delayed(const Duration(milliseconds: 500));
    _showNextMessage();
  }
  
  // チュートリアル完了処理
  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_page_shown', true);
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      );
    }
  }

  Widget _buildMessageBubble(String message, int index) {
    return SlideTransition(
      position: _slideAnimations[index],
      child: FadeTransition(
        opacity: _fadeAnimations[index],
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildGoalSelection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '目標を選択してください',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ..._goalOptions.map((goal) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: () => _selectGoal(goal),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    goal,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.lerp(Colors.white, Theme.of(context).colorScheme.primary, 0.4),
      body: GestureDetector(
        onTap: _showNextMessage,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Column(
            children: [
              // メッセージエリア
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...List.generate(_currentMessageIndex, (index) {
                        if (_currentPhase == 0) {
                          // 初期メッセージ
                          return _buildMessageBubble(_messages[index], index);
                        } else if (_currentPhase == 1) {
                          // 目標選択後のメッセージ
                          return _buildMessageBubble(_afterGoalMessages[index], index);
                        } else {
                          // 最終メッセージ
                          return _buildMessageBubble(_finalMessages[index], index);
                        }
                      }),
                      if (_showGoalSelection) _buildGoalSelection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

