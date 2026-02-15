import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';

class ReadingListeningTaskWidget extends StatefulWidget {
  final String title;
  final Map<String, dynamic> task;
  final String taskType;
  final List<dynamic> isCompletedList;
  final String taskDocId;
  final List<dynamic> answers;
  final Function(String taskType, bool completed) onTaskCompletedUpdate;

  const ReadingListeningTaskWidget({
    super.key,
    required this.title,
    required this.task,
    required this.taskType,
    required this.isCompletedList,
    required this.taskDocId,
    required this.answers,
    required this.onTaskCompletedUpdate,
  });

  @override
  State<ReadingListeningTaskWidget> createState() => _ReadingListeningTaskWidgetState();
}

class _ReadingListeningTaskWidgetState extends State<ReadingListeningTaskWidget> {
  late Map<String, dynamic> _task;
  late List<dynamic> _localAnswers;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  String? currentAudioUrl;
  
  // StreamSubscriptionを追加してリスナーを管理
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;

  @override
  void initState() {
    super.initState();
    _task = Map<String, dynamic>.from(widget.task);
    _localAnswers = List.from(widget.answers);
    _setupAudioPlayer();
  }

  @override
  void didUpdateWidget(ReadingListeningTaskWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      _task = Map<String, dynamic>.from(widget.task);
    }
    if (oldWidget.answers != widget.answers) {
      _localAnswers = List.from(widget.answers);
    }
  }

  void _setupAudioPlayer() {
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (mounted) {
        setState(() {
          isPlaying = state == PlayerState.playing;
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration position) {
      if (mounted) {
        setState(() {
          currentPosition = position;
        });
      }
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((Duration duration) {
      if (mounted) {
        setState(() {
          totalDuration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    // StreamSubscriptionを解除
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    // AudioPlayerを解除
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio(String audioUrl) async {
    try {
      if (isPlaying && currentAudioUrl == audioUrl) {
        await _audioPlayer.pause();
      } else {
        if (currentAudioUrl != audioUrl) {
          await _audioPlayer.play(UrlSource(audioUrl));
          currentAudioUrl = audioUrl;
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      print('Audio toggle error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('音声の再生に失敗しました'),
        ),
      );
    }
  }

  Future<void> _seekAudio(Duration position) async {
    await _audioPlayer.seek(position);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _buildAudioPlayer(String audioUrl) {
    final bool isCurrentAudio = currentAudioUrl == audioUrl;
    final bool showProgress = isCurrentAudio && totalDuration.inMilliseconds > 0;
    
    return Row(
      children: [
        // Play/Pause button
        GestureDetector(
          onTap: () => _toggleAudio(audioUrl),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              (isPlaying && isCurrentAudio) ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Seek bar
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
            ),
            child: Slider(
              value: totalDuration.inMilliseconds > 0
                  ? currentPosition.inMilliseconds / totalDuration.inMilliseconds
                  : 0.0,
              onChanged: (value) {
                final position = Duration(
                  milliseconds: (value * totalDuration.inMilliseconds).round(),
                );
                _seekAudio(position);
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Time display
        Text(
          showProgress 
              ? '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}'
              : '00:00 / 00:00',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
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
    final String text = _task['text'] ?? '';
    final List<dynamic> questions = _task['questions'] ?? [];
    final String? audioUrl = _task['audioUrl'];

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
          
          // Text content with wider card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.taskType.contains('listening')) ...[
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.6,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Georgia',
                    ),
                  ),
                ],
                if (widget.taskType.contains('listening') && audioUrl != null) ...[
                  if (!widget.taskType.contains('listening')) const SizedBox(height: 16),
                  _buildAudioPlayer(audioUrl),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Questions
          ...questions.asMap().entries.map((entry) {
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
          
          // Script display for completed listening tasks
          if (isCompleted && (widget.taskType == 'listening' || widget.taskType == 'listening_sparked')) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.text_snippet,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'スクリプト',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.6,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Georgia',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
