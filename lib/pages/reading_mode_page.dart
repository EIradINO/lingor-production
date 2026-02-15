import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReadingModePage extends StatefulWidget {
  final String documentId;
  final String title;

  const ReadingModePage({
    super.key,
    required this.documentId,
    required this.title,
  });

  @override
  State<ReadingModePage> createState() => _ReadingModePageState();
}

class _ReadingModePageState extends State<ReadingModePage> {
  String? _transcription;
  bool _isLoading = true;
  String? _error;
  double _fontSize = 18.0;
  double _lineHeight = 1.8;

  @override
  void initState() {
    super.initState();
    _loadTranscription();
  }

  Future<void> _loadTranscription() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'ログインが必要です';
          _isLoading = false;
        });
        return;
      }

      // Firestoreから文字起こしデータを取得
      final docSnapshot = await FirebaseFirestore.instance
          .collection('user_documents')
          .doc(widget.documentId)
          .get();

      if (!docSnapshot.exists) {
        setState(() {
          _error = 'ドキュメントが見つかりません';
          _isLoading = false;
        });
        return;
      }

      final docData = docSnapshot.data();
      final transcription = docData?['transcription'] as String?;

      if (transcription == null || transcription.isEmpty) {
        setState(() {
          _error = '文字起こしデータがありません';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _transcription = transcription;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'データの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6E5), // より暖かいアイボリー系
      appBar: AppBar(
        title: Text(
          'Reading Mode',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        backgroundColor: const Color(0xFFFFF6E5),
        foregroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          // フォントサイズ調整ボタン
          PopupMenuButton<String>(
            icon: const Icon(Icons.text_fields, color: Colors.black),
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'small':
                    _fontSize = 16.0;
                    _lineHeight = 1.6;
                    break;
                  case 'medium':
                    _fontSize = 18.0;
                    _lineHeight = 1.8;
                    break;
                  case 'large':
                    _fontSize = 20.0;
                    _lineHeight = 2.0;
                    break;
                  case 'extra_large':
                    _fontSize = 22.0;
                    _lineHeight = 2.2;
                    break;
                }
              });
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'small',
                child: Text('小', style: TextStyle(fontSize: 16)),
              ),
              PopupMenuItem(
                value: 'medium',
                child: Text('中', style: TextStyle(fontSize: 18)),
              ),
              PopupMenuItem(
                value: 'large',
                child: Text('大', style: TextStyle(fontSize: 20)),
              ),
              PopupMenuItem(
                value: 'extra_large',
                child: Text('特大', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('読み込み中...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadTranscription();
              },
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 本文
            Container(
              width: double.infinity,
              child: Text(
                _transcription!,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                  color: const Color(0xFF121212),
                  fontFamily: 'Georgia', // New York Times/BBC風のセリフフォント
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            
            // 下部のスペース
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
