import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/document_file.dart';

// コールバック型定義
typedef OnFileDeleted = void Function(DocumentFile file);
typedef OnTranscriptionView = void Function(DocumentFile file);
typedef OnSavorAnalyze = void Function(String documentId);
typedef OnSavorResultView = void Function(DocumentFile file);
typedef OnTitleEdit = void Function(DocumentFile file, String newTitle);

class DocumentFileCard extends StatefulWidget {
  final DocumentFile file;
  final OnFileDeleted? onFileDeleted;
  final OnTranscriptionView? onTranscriptionView;
  final OnSavorAnalyze? onSavorAnalyze;
  final OnSavorResultView? onSavorResultView;
  final OnTitleEdit? onTitleEdit;

  const DocumentFileCard({
    super.key,
    required this.file,
    this.onFileDeleted,
    this.onTranscriptionView,
    this.onSavorAnalyze,
    this.onSavorResultView,
    this.onTitleEdit,
  });

  @override
  State<DocumentFileCard> createState() => _DocumentFileCardState();
}

class _DocumentFileCardState extends State<DocumentFileCard> {
  String? _currentStatus;
  
  @override
  void initState() {
    super.initState();
    _currentStatus = widget.file.status;
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '不明';
    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case '解析済み':
        return Colors.green;
      case '未解析':
        return Colors.orange;
      case '処理中':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('user_documents')
          .doc(widget.file.id)
          .snapshots(),
      builder: (context, snapshot) {
        String currentStatus = _currentStatus ?? '未解析';
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          currentStatus = data?['status'] ?? '未解析';
        }
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16)
          ),
          child: InkWell(
            onTap: () {
              // カード全体をタップするとsavor_result_pageに遷移
              if (widget.onSavorResultView != null) {
                widget.onSavorResultView!(widget.file);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.file.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(currentStatus),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                currentStatus,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatDateTime(widget.file.createdAt),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.black87,
                    ),
                    onPressed: () => _showBottomSheet(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('タイトルを編集'),
                onTap: () {
                  Navigator.pop(context);
                  _showTitleEditDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('削除'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTitleEditDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(text: widget.file.title);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('タイトルを編集'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'タイトル',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty && widget.onTitleEdit != null) {
                  widget.onTitleEdit!(widget.file, newTitle);
                }
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ファイル削除'),
          content: Text('「${widget.file.title}」を削除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (widget.onFileDeleted != null) {
                  widget.onFileDeleted!(widget.file);
                }
              },
              child: const Text('削除'),
            ),
          ],
        );
      },
    );
  }


} 