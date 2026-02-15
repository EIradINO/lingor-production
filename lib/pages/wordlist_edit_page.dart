import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WordlistEditPage extends StatefulWidget {
  final User user;
  final String listId;
  final String initialTitle;

  const WordlistEditPage({
    super.key,
    required this.user,
    required this.listId,
    required this.initialTitle,
  });

  @override
  State<WordlistEditPage> createState() => _WordlistEditPageState();
}

class _WordlistEditPageState extends State<WordlistEditPage> {
  late TextEditingController _titleController;
  List<String> _wordOrder = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _loadWordOrder();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadWordOrder() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_wordlists')
          .doc(widget.listId)
          .get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final wordOrder = data['word_order'] as List<dynamic>?;
        if (wordOrder != null) {
          setState(() {
            _wordOrder = wordOrder.map((e) => e.toString()).toList();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('単語の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _saveTitle() async {
    try {
      await FirebaseFirestore.instance
          .collection('user_wordlists')
          .doc(widget.listId)
          .update({
        'title': _titleController.text,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('タイトルを保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('タイトルの保存に失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _saveWordOrder() async {
    try {
      await FirebaseFirestore.instance
          .collection('user_wordlists')
          .doc(widget.listId)
          .update({
        'word_order': _wordOrder,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('順番の保存に失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _addWordsFromOtherLists() async {
    final selectedWords = await showDialog<List<String>>(
      context: context,
      builder: (context) => WordSelectionDialog(
        user: widget.user,
        currentListId: widget.listId,
      ),
    );

    if (selectedWords != null && selectedWords.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      try {
        // 選択された単語をこのリストに追加
        for (final wordId in selectedWords) {
          // user_wordsを検索して、list_idに追加
          final userWordsQuery = await FirebaseFirestore.instance
              .collection('user_words')
              .where('user_id', isEqualTo: widget.user.uid)
              .where('word_id', isEqualTo: wordId)
              .limit(1)
              .get();

          if (userWordsQuery.docs.isNotEmpty) {
            final userWordDoc = userWordsQuery.docs.first;
            final data = userWordDoc.data();
            final listIds = List<String>.from(data['list_id'] ?? []);
            
            if (!listIds.contains(widget.listId)) {
              listIds.add(widget.listId);
              await userWordDoc.reference.update({
                'list_id': listIds,
              });
            }
          }

          // word_orderに追加
          if (!_wordOrder.contains(wordId)) {
            _wordOrder.add(wordId);
          }
        }

        await _saveWordOrder();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('単語を追加しました')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('単語の追加に失敗しました: $e')),
          );
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeWord(String wordId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // user_wordsからlist_idを削除
      final userWordsQuery = await FirebaseFirestore.instance
          .collection('user_words')
          .where('user_id', isEqualTo: widget.user.uid)
          .where('word_id', isEqualTo: wordId)
          .limit(1)
          .get();

      if (userWordsQuery.docs.isNotEmpty) {
        final userWordDoc = userWordsQuery.docs.first;
        final data = userWordDoc.data();
        final listIds = List<String>.from(data['list_id'] ?? []);
        listIds.remove(widget.listId);
        
        await userWordDoc.reference.update({
          'list_id': listIds,
        });
      }

      // word_orderから削除
      setState(() {
        _wordOrder.remove(wordId);
      });
      
      await _saveWordOrder();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('単語を削除しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('単語の削除に失敗しました: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('単語帳編集'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTitle,
          ),
        ],
      ),
      body: Column(
        children: [
          // タイトル編集
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          // 単語追加ボタン
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _addWordsFromOtherLists,
                icon: const Icon(Icons.add),
                label: const Text('単語を追加'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 単語リスト
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _wordOrder.isEmpty
                    ? const Center(
                        child: Text(
                          '単語を追加してください',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: _wordOrder.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final item = _wordOrder.removeAt(oldIndex);
                            _wordOrder.insert(newIndex, item);
                          });
                          _saveWordOrder();
                        },
                        itemBuilder: (context, index) {
                          final wordId = _wordOrder[index];
                          return FutureBuilder<DocumentSnapshot>(
                            key: ValueKey(wordId),
                            future: FirebaseFirestore.instance
                                .collection('dictionary')
                                .doc(wordId)
                                .get(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || !snapshot.data!.exists) {
                                return ListTile(
                                  key: ValueKey(wordId),
                                  title: const Text('読み込み中...'),
                                );
                              }

                              final data = snapshot.data!.data() as Map<String, dynamic>;
                              final word = data['original_word'] ?? data['word'] ?? '不明';
                              final meanings = data['meanings'];
                              String meaningText = '';
                              
                              if (meanings is List && meanings.isNotEmpty) {
                                if (meanings[0] is Map) {
                                  meaningText = meanings[0]['definition'] ?? '';
                                } else if (meanings[0] is String) {
                                  meaningText = meanings[0];
                                }
                              }

                              return Card(
                                key: ValueKey(wordId),
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.drag_handle),
                                  title: Text(
                                    word,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  subtitle: meaningText.isNotEmpty
                                      ? Text(
                                          meaningText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _removeWord(wordId),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class WordSelectionDialog extends StatefulWidget {
  final User user;
  final String currentListId;

  const WordSelectionDialog({
    super.key,
    required this.user,
    required this.currentListId,
  });

  @override
  State<WordSelectionDialog> createState() => _WordSelectionDialogState();
}

class _WordSelectionDialogState extends State<WordSelectionDialog> {
  String _selectedListId = 'ALL'; // デフォルトで「すべて」を選択
  Set<String> _selectedWords = {};
  List<Map<String, dynamic>> _words = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 初期表示時に全ての単語を読み込む
    _loadWordsFromList('ALL');
  }

  Future<void> _loadWordsFromList(String listId) async {
    setState(() {
      _isLoading = true;
      _words = [];
      _selectedWords.clear();
    });

    try {
      final QuerySnapshot userWordsQuery;
      
      if (listId == 'ALL') {
        // 「すべて」が選択された場合は全ての単語を取得
        userWordsQuery = await FirebaseFirestore.instance
            .collection('user_words')
            .where('user_id', isEqualTo: widget.user.uid)
            .get();
      } else {
        // 特定のリストが選択された場合
        userWordsQuery = await FirebaseFirestore.instance
            .collection('user_words')
            .where('user_id', isEqualTo: widget.user.uid)
            .where('list_id', arrayContains: listId)
            .get();
      }

      final words = <Map<String, dynamic>>[];
      
      for (final doc in userWordsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final wordId = data['word_id'] as String?;
        
        if (wordId != null) {
          final dictDoc = await FirebaseFirestore.instance
              .collection('dictionary')
              .doc(wordId)
              .get();
          
          if (dictDoc.exists) {
            final dictData = dictDoc.data() as Map<String, dynamic>;
            words.add({
              'word_id': wordId,
              'word': dictData['original_word'] ?? dictData['word'] ?? '不明',
              'meanings': dictData['meanings'],
            });
          }
        }
      }

      setState(() {
        _words = words;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('単語の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  void _selectAll() {
    setState(() {
      _selectedWords = _words.map((w) => w['word_id'] as String).toSet();
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedWords.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '単語を選択',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 単語帳選択
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('user_wordlists')
                  .where('user_id', isEqualTo: widget.user.uid)
                  .orderBy('created_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final wordlists = snapshot.data!.docs
                    .where((doc) => doc.id != widget.currentListId)
                    .toList();

                // 「すべて」オプションを最初に追加
                final items = <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: 'ALL',
                    child: Text('すべて'),
                  ),
                  ...wordlists.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? '無題';
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(title),
                    );
                  }),
                ];

                return DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('単語帳を選択'),
                  value: _selectedListId,
                  items: items,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedListId = value;
                      });
                      _loadWordsFromList(value);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            // 全て選択/解除ボタン
            if (_words.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.check_box),
                    label: const Text('全て選択'),
                  ),
                  TextButton.icon(
                    onPressed: _deselectAll,
                    icon: const Icon(Icons.check_box_outline_blank),
                    label: const Text('選択解除'),
                  ),
                ],
              ),
              const Divider(),
            ],
            // 単語リスト
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _words.isEmpty
                      ? const Center(
                          child: Text(
                            '単語帳を選択してください',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _words.length,
                          itemBuilder: (context, index) {
                            final word = _words[index];
                            final wordId = word['word_id'] as String;
                            final wordText = word['word'] as String;
                            final meanings = word['meanings'];
                            
                            String meaningText = '';
                            if (meanings is List && meanings.isNotEmpty) {
                              if (meanings[0] is Map) {
                                meaningText = meanings[0]['definition'] ?? '';
                              } else if (meanings[0] is String) {
                                meaningText = meanings[0];
                              }
                            }

                            return CheckboxListTile(
                              title: Text(
                                wordText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: meaningText.isNotEmpty
                                  ? Text(
                                      meaningText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              value: _selectedWords.contains(wordId),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedWords.add(wordId);
                                  } else {
                                    _selectedWords.remove(wordId);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            // 追加ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedWords.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selectedWords.toList()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('${_selectedWords.length}個の単語を追加'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

