import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SaveWordPage extends StatefulWidget {
  final String dictionaryId;
  final Map<String, dynamic> wordData;
  final List<List<Map<String, dynamic>>> examples;
  final String? initialListId;
  final String? documentId;

  const SaveWordPage({
    super.key,
    required this.dictionaryId,
    required this.wordData,
    required this.examples,
    this.initialListId,
    this.documentId,
  });

  @override
  State<SaveWordPage> createState() => _SaveWordPageState();
}

class _SaveWordPageState extends State<SaveWordPage> {
  List<String> _selectedListIds = []; // 複数選択可能
  List<TextEditingController> _meaningControllers = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _wordLists = [];
  String? _documentTitle;
  bool _saveToDocument = true; // ドキュメントのwordlistに保存するか（デフォルトON）

  @override
  void initState() {
    super.initState();
    // initialListIdがあれば選択リストに追加
    if (widget.initialListId != null && widget.initialListId!.isNotEmpty) {
      _selectedListIds.add(widget.initialListId!);
    }
    _loadMeanings();
    _loadDocumentTitle();
  }

  void _loadMeanings() {
    final List meanings = widget.wordData['meanings'] ?? [];
    final List<String> meaningStrings = meanings.map((meaning) {
      if (meaning is String) {
        return meaning;
      } else if (meaning is Map) {
        // 既存のMap形式の場合はdefinitionを取得
        return (meaning['definition']?.toString() ?? '');
      } else {
        return '';
      }
    }).where((m) => m.isNotEmpty).toList();
    
    // 空の場合は1つ追加
    if (meaningStrings.isEmpty) {
      meaningStrings.add('');
    }

    // コントローラーを初期化
    _meaningControllers = meaningStrings.map((meaning) => TextEditingController(text: meaning)).toList();
  }

  @override
  void dispose() {
    // コントローラーを破棄
    for (var controller in _meaningControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDocumentTitle() async {
    if (widget.documentId == null || widget.documentId!.isEmpty) {
      // ドキュメントIDがない場合は、単語リストのみを読み込む
      _loadWordLists();
      return;
    }

    try {
      final documentDoc = await FirebaseFirestore.instance
          .collection('user_documents')
          .doc(widget.documentId)
          .get();

      if (documentDoc.exists) {
        final documentData = documentDoc.data();
        setState(() {
          _documentTitle = documentData?['title'] ?? '無題のドキュメント';
        });
      }
    } catch (e) {
      print('ドキュメントタイトルの読み込みに失敗: $e');
    } finally {
      // ドキュメントタイトルの読み込み後、単語リストを読み込む
      _loadWordLists();
    }
  }

  Future<void> _loadWordLists() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // user_wordlistsからdocument_idが空文字列のもののみ取得
      final wordlistsQuery = await FirebaseFirestore.instance
          .collection('user_wordlists')
          .where('user_id', isEqualTo: user.uid)
          .where('document_id', isEqualTo: '')
          .get();

      final List<Map<String, dynamic>> lists = [];

      for (final doc in wordlistsQuery.docs) {
        final data = doc.data();
        lists.add({
          'id': doc.id,
          'title': data['title'] ?? '無題のリスト',
          'type': 'wordlist',
        });
      }

      setState(() {
        _wordLists = lists;
        // _selectedListIdsからwordlistsに存在しないid（documentのwordlistのidなど）を除外
        _selectedListIds.removeWhere((id) => !lists.any((list) => list['id'] == id));
      });
    } catch (e) {
      _showMessage('リストの読み込みに失敗しました: $e');
    }
  }

  void _addMeaning() {
    setState(() {
      _meaningControllers.add(TextEditingController(text: ''));
    });
  }

  void _removeMeaning(int index) {
    setState(() {
      _meaningControllers[index].dispose();
      _meaningControllers.removeAt(index);
    });
  }

  Future<void> _saveWord() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }

      List<String> actualListIds = [];
      
      // documentのwordlistを確認・作成（チェックボックスがONの場合のみ）
      if (_saveToDocument && widget.documentId != null && widget.documentId!.isNotEmpty) {
        final wordlistQuery = await FirebaseFirestore.instance
            .collection('user_wordlists')
            .where('document_id', isEqualTo: widget.documentId)
            .where('user_id', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        if (wordlistQuery.docs.isNotEmpty) {
          // 既存のwordlistを使用
          actualListIds.add(wordlistQuery.docs.first.id);
        } else {
          // 新しいwordlistを作成（遅延作成）
          final newWordlist = await FirebaseFirestore.instance
              .collection('user_wordlists')
              .add({
            'user_id': user.uid,
            'document_id': widget.documentId,
            'title': '${_documentTitle ?? 'ドキュメント'}の単語リスト',
            'created_at': FieldValue.serverTimestamp(),
          });
          actualListIds.add(newWordlist.id);
        }
      }
      
      // 選択された他のwordlistsを追加
      actualListIds.addAll(_selectedListIds);
      
      // 重複を除外（念のため）
      actualListIds = actualListIds.toSet().toList();

      // 既に保存済みかチェック
      final query = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: user.uid)
          .where('word_id', isEqualTo: widget.dictionaryId)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _showMessage('この単語は既に追加されています');
        return;
      }

      // 例文をフラット化
      final List<Map<String, dynamic>> flattenedExamples = [];
      for (int meaningIndex = 0; meaningIndex < widget.examples.length; meaningIndex++) {
        final List<Map<String, dynamic>> meaningExamples = widget.examples[meaningIndex];
        for (int exampleIndex = 0; exampleIndex < meaningExamples.length; exampleIndex++) {
          final Map<String, dynamic> example = meaningExamples[exampleIndex];
          final dynamic original = example['original'];
          final dynamic translation = example['translation'];
          if (original is String && translation is String) {
            flattenedExamples.add({
              'original': original,
              'translation': translation,
              'meaningIndex': meaningIndex,
            });
          }
        }
      }

      // 空の意味は除外
      final validMeanings = _meaningControllers
          .map((controller) => controller.text)
          .where((meaning) => meaning.trim().isNotEmpty)
          .toList();

      final Map<String, dynamic> wordData = {
        'user_id': user.uid,
        'word_id': widget.dictionaryId,
        'list_id': actualListIds, // 配列として保存
        'created_at': FieldValue.serverTimestamp(),
        'isCorrectData': [],
        'stage': 'vocabulary',
        'examples': flattenedExamples,
        'meanings': validMeanings,
        if (_documentTitle != null) 'document_title': _documentTitle,
      };

      await FirebaseFirestore.instance
          .collection('user_words')
          .add(wordData);

      // dictionaryコレクションのsaved_usersを1増加
      final dictionaryRef = FirebaseFirestore.instance
          .collection('dictionary')
          .doc(widget.dictionaryId);
      await dictionaryRef.update({
        'saved_users': FieldValue.increment(1),
      });

      if (mounted) {
        Navigator.of(context).pop(true); // 保存成功を返す
      }
    } catch (e) {
      _showMessage('保存に失敗しました: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // キーボードのフォーカスを外す
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('単語を保存'),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: Column(
          children: [
            const Divider(height: 1),
            // コンテンツ
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // documentIdが存在する場合のみチェックボックスを表示
                    if (widget.documentId != null && widget.documentId!.isNotEmpty) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'このドキュメントの単語リストに保存',
                          style: TextStyle(
                            fontSize: 15,
                            color: _saveToDocument ? Theme.of(context).colorScheme.primary : Colors.black87,
                            fontWeight: _saveToDocument ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: _documentTitle != null
                            ? Text(
                                _documentTitle!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              )
                            : null,
                        value: _saveToDocument,
                        onChanged: (value) {
                          setState(() {
                            _saveToDocument = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    // 保存先リスト選択（複数選択可能）
                    const Text(
                      '他の単語リストにも保存（任意）',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_wordLists.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '他の単語リストがありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _wordLists.length,
                          itemBuilder: (context, index) {
                            final list = _wordLists[index];
                            final listId = list['id'] as String;
                            final isSelected = _selectedListIds.contains(listId);
                            
                            return CheckboxListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              title: Row(
                                children: [
                                  Icon(
                                    Icons.list,
                                    size: 18,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      list['title'] as String,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedListIds.add(listId);
                                  } else {
                                    _selectedListIds.remove(listId);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),
                    // 意味編集セクション
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '意味',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addMeaning,
                          icon: const Icon(Icons.add),
                          label: const Text('追加'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  ..._meaningControllers.asMap().entries.map((entry) {
                    final index = entry.key;
                    return _buildMeaningEditor(index);
                  }),
                  ],
                ),
              ),
            ),
            // 保存ボタン
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveWord,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '保存',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeaningEditor(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _meaningControllers[index],
              decoration: InputDecoration(
                labelText: '意味 ${index + 1}',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => _removeMeaning(index),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

