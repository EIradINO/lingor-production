import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../gem_purchase_widget.dart';

// コールバック型定義
typedef OnFileSelected = void Function();
typedef OnTextSelected = void Function();
typedef OnDocumentScanSelected = void Function();
typedef OnPhotosSelected = void Function();
typedef OnTakePhotosSelected = void Function();

class FileSelectionBottomSheet extends StatefulWidget {
  final OnFileSelected? onFileSelected;
  final OnTextSelected? onTextSelected;
  final OnDocumentScanSelected? onDocumentScanSelected;
  final OnPhotosSelected? onPhotosSelected;
  final OnTakePhotosSelected? onTakePhotosSelected;

  const FileSelectionBottomSheet({
    super.key,
    this.onFileSelected,
    this.onTextSelected,
    this.onDocumentScanSelected,
    this.onPhotosSelected,
    this.onTakePhotosSelected,
  });

  @override
  State<FileSelectionBottomSheet> createState() => _FileSelectionBottomSheetState();
}

// 学習方法の種類
enum LearningMethodType {
  paperMaterial,    // 紙の教材
  digitalMaterial,  // デジタル教材
  gemPurchase,      // GEMを追加
}

class _FileSelectionBottomSheetState extends State<FileSelectionBottomSheet> {
  LearningMethodType? _selectedMethod;
  String _userPlan = 'free';
  
  @override
  void initState() {
    super.initState();
    _loadUserPlan();
  }
  
  // ユーザーのプラン情報を読み込み
  Future<void> _loadUserPlan() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final data = userDoc.data();
          final plan = data?['plan'] ?? 'free';
          setState(() {
            _userPlan = plan;
          });
        } else {
          setState(() {
            _userPlan = 'free';
          });
        }
      } else {
        setState(() {
          _userPlan = 'free';
        });
      }
    } catch (e) {
      setState(() {
        _userPlan = 'free';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダー部分
              Row(
                children: [
                  if (_selectedMethod != null)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _selectedMethod = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      _selectedMethod == null
                          ? '学習方法を選択'
                          : _selectedMethod == LearningMethodType.gemPurchase
                              ? 'GEMを追加'
                              : '教材を選択',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_selectedMethod != null)
                    const SizedBox(width: 48), // Back buttonとのバランスを取るため
                ],
              ),
              const SizedBox(height: 16),
              
              // メインコンテンツ
              if (_selectedMethod == null)
                _buildMethodSelection()
              else if (_selectedMethod == LearningMethodType.gemPurchase)
                _buildGemPurchaseContent()
              else
                _buildActionSelection(_selectedMethod!),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 第一段階：学習方法選択
  Widget _buildMethodSelection() {
    // standard または pro プランの場合はGEM追加を表示しない
    final shouldShowGemPurchase = _userPlan.toLowerCase() != 'standard' && 
                                   _userPlan.toLowerCase() != 'pro';
    
    return Column(
      children: [
        _buildMethodTile(
          icon: Icons.description,
          title: '紙の教材を学ぶ',
          subtitle: '書類をスキャン、写真を撮影',
          onTap: () {
            setState(() {
              _selectedMethod = LearningMethodType.paperMaterial;
            });
          },
        ),
        const Divider(height: 1),
        _buildMethodTile(
          icon: Icons.computer,
          title: 'デジタル教材を学ぶ',
          subtitle: 'テキスト入力、PDF・音声ファイル、写真選択',
          onTap: () {
            setState(() {
              _selectedMethod = LearningMethodType.digitalMaterial;
            });
          },
        ),
        if (shouldShowGemPurchase) ...[
          const Divider(height: 1),
          _buildMethodTile(
            icon: Icons.diamond,
            title: 'GEMを追加',
            subtitle: '広告視聴またはアプリ内購入でGEMを追加',
            onTap: () {
              setState(() {
                _selectedMethod = LearningMethodType.gemPurchase;
              });
            },
          ),
        ],
      ],
    );
  }

  // GEM購入コンテンツ
  Widget _buildGemPurchaseContent() {
    return const GemPurchaseWidget();
  }

  // 第二段階：具体的なアクション選択
  Widget _buildActionSelection(LearningMethodType method) {
    switch (method) {
      case LearningMethodType.paperMaterial:
        return _buildPaperMaterialActions();
      case LearningMethodType.digitalMaterial:
        return _buildDigitalMaterialActions();
      case LearningMethodType.gemPurchase:
        return _buildGemPurchaseContent();
    }
  }

  // 紙の教材用アクション
  Widget _buildPaperMaterialActions() {
    return Column(
      children: [
        _buildSelectionTile(
          icon: Icons.document_scanner,
          title: '書類をスキャン',
          onTap: () {
            Navigator.pop(context);
            if (widget.onDocumentScanSelected != null) {
              widget.onDocumentScanSelected!();
            }
          },
        ),
        _buildSelectionTile(
          icon: Icons.camera_alt,
          title: '写真を撮影(4枚まで)',
          onTap: () {
            Navigator.pop(context);
            if (widget.onTakePhotosSelected != null) {
              widget.onTakePhotosSelected!();
            }
          },
        ),
      ],
    );
  }

  // デジタル教材用アクション
  Widget _buildDigitalMaterialActions() {
    return Column(
      children: [
        _buildSelectionTile(
          icon: Icons.text_fields,
          title: 'テキストをコピー&ペースト',
          onTap: () {
            Navigator.pop(context);
            if (widget.onTextSelected != null) {
              widget.onTextSelected!();
            }
          },
        ),
        _buildSelectionTile(
          icon: Icons.insert_drive_file,
          title: 'PDF・音声ファイルを選択',
          onTap: () {
            Navigator.pop(context);
            if (widget.onFileSelected != null) {
              widget.onFileSelected!();
            }
          },
        ),
        _buildSelectionTile(
          icon: Icons.photo_library,
          title: '写真を選択(4枚まで)',
          onTap: () {
            Navigator.pop(context);
            if (widget.onPhotosSelected != null) {
              widget.onPhotosSelected!();
            }
          },
        ),
      ],
    );
  }

  // 学習方法選択用のタイル
  Widget _buildMethodTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      leading: Icon(icon, size: 24, color: Theme.of(context).primaryColor),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildSelectionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Icon(icon, color: Theme.of(context).primaryColor),
      ),
      title: Text(title),
      onTap: onTap,
    );
  }
} 