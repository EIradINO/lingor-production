import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SpeechToTextPage extends StatefulWidget {
  final String? documentId;
  
  const SpeechToTextPage({super.key, this.documentId});

  @override
  State<SpeechToTextPage> createState() => _SpeechToTextPageState();
}

class _SpeechToTextPageState extends State<SpeechToTextPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  
  String? _originalAudioUrl;
  String? _overlappingAudioUrl;
  List<Map<String, dynamic>> _timestampedSentences = [];
  bool _useOverlappingMode = false;
  int _currentSentenceIndex = -1;

  // リスナーの購読を管理するためのStreamSubscription
  late final StreamSubscription _durationSubscription;
  late final StreamSubscription _positionSubscription;
  late final StreamSubscription _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
    _loadAudioData();
  }

  @override
  void dispose() {
    _durationSubscription.cancel();
    _positionSubscription.cancel();
    _playerStateSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _setupAudioPlayer() {
    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
          // 現在のセンテンスを更新（両方のモードで）
          _updateCurrentSentenceIndex();
        });
      }
    });

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> _loadAudioData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // user_audiosコレクションから音声データを取得
      QuerySnapshot audioSnapshot;
      if (widget.documentId != null) {
        audioSnapshot = await FirebaseFirestore.instance
            .collection('user_audios')
            .where('user_id', isEqualTo: user.uid)
            .where('document_id', isEqualTo: widget.documentId)
            .limit(1)
            .get();
      } else {
        audioSnapshot = await FirebaseFirestore.instance
            .collection('user_audios')
            .where('user_id', isEqualTo: user.uid)
            .orderBy('created_at', descending: true)
            .limit(1)
            .get();
      }

      if (audioSnapshot.docs.isNotEmpty) {
        final audioData = audioSnapshot.docs.first.data() as Map<String, dynamic>;
        
        // Storage URLを取得
        final storage = FirebaseStorage.instanceFor(bucket: 'gs://lingosavor');
        final originalPath = audioData['original_path'] as String;
        final overlappingPath = audioData['overlapping_path'] as String;
        
        _originalAudioUrl = await storage.ref(originalPath).getDownloadURL(); // refを使用
        _overlappingAudioUrl = await storage.ref(overlappingPath).getDownloadURL(); // refを使用
        
        _timestampedSentences = List<Map<String, dynamic>>.from(
          audioData['timestamped_sentences'] ?? []
        );
        
        // デフォルトで元音声を設定
        await _audioPlayer.setSourceUrl(_originalAudioUrl!);
      }
    } catch (e) {
      print('Error loading audio data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.resume();
    }
  }

  Future<void> _switchToMode(bool overlappingMode) async {
    setState(() {
      _useOverlappingMode = overlappingMode;
    });
    
    // モードに応じて音声を切り替え
    if (_useOverlappingMode && _overlappingAudioUrl != null) {
      await _audioPlayer.setSourceUrl(_overlappingAudioUrl!);
    } else if (_originalAudioUrl != null) {
      await _audioPlayer.setSourceUrl(_originalAudioUrl!);
    }
  }

  Future<void> _seekToTimestamp(String timestamp) async {
    final totalMilliseconds = _timestampToMilliseconds(timestamp);
    
    if (_useOverlappingMode) {
      // オーバーラッピングモードでは、実際の再生位置を計算
      final overlappingPosition = _calculateOverlappingPosition(timestamp);
      await _audioPlayer.seek(Duration(milliseconds: overlappingPosition));
    } else {
      // 通常モードでは元のタイムスタンプを使用
      await _audioPlayer.seek(Duration(milliseconds: totalMilliseconds));
    }
  }

  // タイムスタンプをミリ秒に変換するヘルパー関数（ミリ秒感覚のみ対応）
  int _timestampToMilliseconds(String timestamp) {
    final parts = timestamp.split(':');
    
    if (parts.length == 3) {
      // MM:SS:mmm形式（例: "00:03:834" -> 3秒834ミリ秒）
      final minutes = int.parse(parts[0]);
      final seconds = int.parse(parts[1]);
      final milliseconds = int.parse(parts[2]);
      return minutes * 60 * 1000 + seconds * 1000 + milliseconds;
    }
    
    throw Exception('Invalid timestamp format: $timestamp (only MM:SS:mmm format supported, e.g., "00:03:834")');
  }

  // オーバーラッピング音声での再生位置を計算（ミリ秒単位）
  int _calculateOverlappingPosition(String targetTimestamp) {
    int cumulativeMilliseconds = 0;
    
    for (int i = 0; i < _timestampedSentences.length; i++) {
      final item = _timestampedSentences[i];
      final timestamp = item['timestamp'] as String;
      
      if (timestamp == targetTimestamp) {
        return cumulativeMilliseconds;
      }
      
      // このセグメントの長さを計算（ミリ秒単位）
      final currentStartMs = _timestampToMilliseconds(timestamp);
      
      int segmentDurationMs;
      if (i + 1 < _timestampedSentences.length) {
        final nextItem = _timestampedSentences[i + 1];
        final nextTimestamp = nextItem['timestamp'] as String;
        final nextStartMs = _timestampToMilliseconds(nextTimestamp);
        segmentDurationMs = nextStartMs - currentStartMs;
      } else {
        // 最後のセグメントの場合、推定値を使用（元音声の長さから計算）
        segmentDurationMs = _duration.inMilliseconds - currentStartMs;
      }
      
      // セグメント + 同じ長さの沈黙
      cumulativeMilliseconds += segmentDurationMs * 2;
    }
    
    return cumulativeMilliseconds;
  }

  // 現在のセンテンスインデックスを更新
  void _updateCurrentSentenceIndex() {
    if (!mounted || _timestampedSentences.isEmpty) {
      _currentSentenceIndex = -1;
      return;
    }

    if (_useOverlappingMode) {
      _updateCurrentSentenceIndexForOverlapping();
    } else {
      _updateCurrentSentenceIndexForDefault();
    }
  }

  // Defaultモード用の現在のセンテンスインデックス更新
  void _updateCurrentSentenceIndexForDefault() {
    final currentPositionMs = _position.inMilliseconds;

    for (int i = 0; i < _timestampedSentences.length; i++) {
      final timestamp = _timestampedSentences[i]['timestamp'] as String;
      final currentStartMs = _timestampToMilliseconds(timestamp);
      
      int segmentDurationMs;
      if (i + 1 < _timestampedSentences.length) {
        final nextTimestamp = _timestampedSentences[i + 1]['timestamp'] as String;
        final nextStartMs = _timestampToMilliseconds(nextTimestamp);
        segmentDurationMs = nextStartMs - currentStartMs;
      } else {
        segmentDurationMs = _duration.inMilliseconds - currentStartMs;
      }

      // 音声部分の範囲内かチェック
      if (currentPositionMs >= currentStartMs && 
          currentPositionMs < currentStartMs + segmentDurationMs) {
        _currentSentenceIndex = i;
        return;
      }
    }
    
    _currentSentenceIndex = -1;
  }

  // Overlappingモード用の現在のセンテンスインデックス更新（空白期間も背景維持）
  void _updateCurrentSentenceIndexForOverlapping() {
    int cumulativeMilliseconds = 0;
    final currentPositionMs = _position.inMilliseconds;

    for (int i = 0; i < _timestampedSentences.length; i++) {
      // このセグメントの長さを計算（ミリ秒単位）
      final timestamp = _timestampedSentences[i]['timestamp'] as String;
      final currentStartMs = _timestampToMilliseconds(timestamp);
      
      int segmentDurationMs;
      if (i + 1 < _timestampedSentences.length) {
        final nextTimestamp = _timestampedSentences[i + 1]['timestamp'] as String;
        final nextStartMs = _timestampToMilliseconds(nextTimestamp);
        segmentDurationMs = nextStartMs - currentStartMs;
      } else {
        segmentDurationMs = _duration.inMilliseconds - currentStartMs;
      }

      // 音声部分または空白部分（リピート時間）の範囲内かチェック
      if (currentPositionMs >= cumulativeMilliseconds && 
          currentPositionMs < cumulativeMilliseconds + segmentDurationMs * 2) {
        _currentSentenceIndex = i;
        return;
      }
      
      // セグメント + 沈黙の時間を加算
      cumulativeMilliseconds += segmentDurationMs * 2;
    }
    
    _currentSentenceIndex = -1; // どのセグメントにも該当しない
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds % 60);
    return '$minutes:$seconds';
  }

  Widget _buildSentencesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _timestampedSentences.length,
      itemBuilder: (context, index) {
        final item = _timestampedSentences[index];
        final timestamp = item['timestamp'] as String;
        final sentence = item['sentence'] as String;
        final isCurrentlyPlaying = _currentSentenceIndex == index;

        return Container(
          decoration: BoxDecoration(
            color: isCurrentlyPlaying 
                ? Theme.of(context).primaryColor.withOpacity(0.2)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey[300]!,
                width: 0.5,
              ),
            ),
          ),
          child: ListTile(
            title: Text(
              sentence,
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 14,
              ),
            ),
            onTap: () async {
              await _seekToTimestamp(timestamp);
            },
          ),
        );
      },
    );
  }

  Widget _buildModeTab(String title, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Listening'),
          elevation: 0,
          toolbarHeight: 48,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_originalAudioUrl == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Listening'),
          elevation: 0,
          toolbarHeight: 48,
        ),
        body: const Center(
          child: Text('音声データが見つかりません'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Listening'),
        elevation: 0,
        toolbarHeight: 48,
      ),
      body: Column(
        children: [
          // メインコンテンツ（文章リスト）
          Expanded(
            child: _buildSentencesList(),
          ),
          
          // 下部の再生コントロール
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // モード切り替えタブ
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                                      child: Row(
                      children: [
                        _buildModeTab(
                          'Default', 
                          !_useOverlappingMode,
                          () => _switchToMode(false),
                        ),
                        _buildModeTab(
                          _overlappingAudioUrl != null ? 'Overlapping' : 'No Audio',
                          _useOverlappingMode,
                          _overlappingAudioUrl != null ? () => _switchToMode(true) : () {},
                        ),
                      ],
                    ),
                ),
                
                // 再生ボタンとシークバー
                Row(
                  children: [
                    // 再生ボタン
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Theme.of(context).primaryColor,
                        size: 48,
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // 現在時間表示
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // シークバー
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbColor: Theme.of(context).primaryColor,
                          activeTrackColor: Theme.of(context).primaryColor,
                          inactiveTrackColor: Colors.grey[300],
                        ),
                        child: Slider(
                          value: _position.inSeconds.toDouble(),
                          max: _duration.inSeconds.toDouble(),
                          onChanged: (value) async {
                            await _audioPlayer.seek(Duration(seconds: value.toInt()));
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // 総時間表示
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 