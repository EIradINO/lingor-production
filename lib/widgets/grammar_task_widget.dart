import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GrammarTaskWidget extends StatefulWidget {
  final String title;
  final List<dynamic> grammarList;
  final String taskType;
  final List<dynamic> isCompletedList;
  final String taskDocId;
  final List<dynamic> answers;
  final Function(String taskType, bool completed) onTaskCompletedUpdate;

  const GrammarTaskWidget({
    super.key,
    required this.title,
    required this.grammarList,
    required this.taskType,
    required this.isCompletedList,
    required this.taskDocId,
    required this.answers,
    required this.onTaskCompletedUpdate,
  });

  @override
  State<GrammarTaskWidget> createState() => _GrammarTaskWidgetState();
}

class _GrammarTaskWidgetState extends State<GrammarTaskWidget> {
  late List<dynamic> _grammarList;
  late List<dynamic> _localAnswers;

  @override
  void initState() {
    super.initState();
    _grammarList = List.from(widget.grammarList);
    _localAnswers = List.from(widget.answers);
  }

  @override
  void didUpdateWidget(GrammarTaskWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grammarList != widget.grammarList) {
      _grammarList = List.from(widget.grammarList);
    }
    if (oldWidget.answers != widget.answers) {
      _localAnswers = List.from(widget.answers);
    }
  }

  Future<void> _answerQuestion(int questionIndex, int selectedOption) async {
    try {
      // ローカル状態を即座に更新（UI即座反映のため）
      setState(() {
        // 配列のサイズを調整（必要に応じて拡張）
        while (_localAnswers.length <= questionIndex) {
          _localAnswers.add(-1);
        }
        _localAnswers[questionIndex] = selectedOption;
      });

      // 現在のタスクドキュメントを取得
      final docSnapshot = await FirebaseFirestore.instance
          .collection('user_tasks')
          .doc(widget.taskDocId)
          .get();
      
      if (!docSnapshot.exists) {
        throw Exception('タスクドキュメントが見つかりません');
      }
      
      final data = docSnapshot.data();
      if (data == null) {
        throw Exception('ドキュメントデータが無効です');
      }
      
      // answers配列を取得（存在しない場合は空のMapを作成）
      Map<String, dynamic> answers = Map<String, dynamic>.from(data['answers'] ?? {});
      
      // 該当のタスクタイプの配列を取得（存在しない場合は初期化）
      List<dynamic> currentAnswers = List<dynamic>.from(answers[widget.taskType] ?? []);
      
      // 配列のサイズを調整（必要に応じて拡張）
      while (currentAnswers.length <= questionIndex) {
        currentAnswers.add(-1);
      }
      
      // 該当位置の回答を更新
      currentAnswers[questionIndex] = selectedOption;
      
      // answers配列を更新
      answers[widget.taskType] = currentAnswers;
      
      // Firestoreに保存
      await FirebaseFirestore.instance
          .collection('user_tasks')
          .doc(widget.taskDocId)
          .update({'answers': answers});

      // 全問題が回答されたかチェック
      _checkTaskCompletion();
      
    } catch (e) {
      print('Answer update error: $e');
      // エラーが発生した場合はローカル状態を元に戻す
      setState(() {
        if (questionIndex < _localAnswers.length) {
          _localAnswers[questionIndex] = -1;
        }
      });
    }
  }

  void _checkTaskCompletion() {
    bool allAnswered = true;
    
    for (int i = 0; i < _localAnswers.length; i++) {
      if (_localAnswers[i] == -1) {
        allAnswered = false;
        break;
      }
    }
    
    if (allAnswered && !widget.isCompletedList.contains(widget.taskType)) {
      widget.onTaskCompletedUpdate(widget.taskType, true);
    }
  }

  Widget _buildQuestionWidget(
    int questionIndex,
    String questionText,
    List<String> options,
    int correctAnswer,
    bool isTaskCompleted,
  ) {
    // ローカルanswers配列から回答を取得
    int selectedAnswer = -1;
    if (questionIndex < _localAnswers.length) {
      selectedAnswer = _localAnswers[questionIndex];
    }
    
    final bool isAnswered = selectedAnswer != -1;
    final bool isCorrect = isAnswered && selectedAnswer == correctAnswer;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${questionIndex + 1}: $questionText',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.6,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 12),
          
          ...options.asMap().entries.map((entry) {
            final int optionIndex = entry.key;
            final String option = entry.value;
            
            Color? backgroundColor;
            Color? textColor;
            IconData? icon;
            
            if (isAnswered) {
              if (optionIndex == correctAnswer) {
                backgroundColor = Colors.green.withOpacity(0.2);
                textColor = Colors.green[700];
                icon = Icons.check;
              } else if (optionIndex == selectedAnswer && selectedAnswer != correctAnswer) {
                backgroundColor = Colors.red.withOpacity(0.2);
                textColor = Colors.red[700];
                icon = Icons.close;
              } else {
                backgroundColor = Colors.grey[100];
                textColor = Colors.grey[600];
              }
            } else {
              backgroundColor = Colors.grey[50];
              textColor = Colors.black87;
            }
            
            return GestureDetector(
              onTap: isAnswered ? null : () => _answerQuestion(questionIndex, optionIndex),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAnswered && optionIndex == selectedAnswer
                        ? (isCorrect ? Colors.green : Colors.red)
                        : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      String.fromCharCode(65 + optionIndex), // A, B, C, D
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontFamily: 'Georgia',
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 16,
                          color: textColor,
                          height: 1.6,
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ),
                    if (icon != null)
                      Icon(
                        icon,
                        color: textColor,
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = widget.isCompletedList.contains(widget.taskType);

    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(
                isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isCompleted ? Colors.green : Colors.grey[400],
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Grammar questions
          ..._grammarList.asMap().entries.map((entry) {
            final int questionIndex = entry.key;
            final Map<String, dynamic> question = entry.value;
            final String questionText = question['question'] ?? '';
            final List<dynamic> options = question['options'] ?? [];
            final int correctAnswer = question['answer'] ?? 0;
            
            return _buildQuestionWidget(
              questionIndex,
              questionText,
              options.cast<String>(),
              correctAnswer,
              isCompleted,
            );
          }).toList(),
        ],
      ),
    );
  }
}
