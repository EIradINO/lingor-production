import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:io';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'savor_result_page.dart';
import '../services/admob_service.dart';

// 新規作成したウィジェットとモデルをインポート
import '../models/document_file.dart';
import '../widgets/documents/empty_state_widget.dart';
import '../widgets/documents/document_file_card.dart';
import '../widgets/documents/file_selection_bottom_sheet.dart';
import 'transcription_type_page.dart';
import 'transcription_edit_page.dart';
import 'text_input_page.dart';
import 'package:pdf_render/pdf_render.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

// GlobalKeyを使用してDocumentsPageの状態にアクセスできるようにする
final GlobalKey<State<DocumentsPage>> documentsPageKey = GlobalKey<State<DocumentsPage>>();

class _DocumentsPageState extends State<DocumentsPage> {

  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: 'gs://lingosavor');
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isUploading = false;
  bool _isLoading = true;
  List<DocumentFile> _uploadedFiles = [];

  // AdMob関連
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  // Firebase Functions インスタンス
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // チュートリアル用のGlobalKey
  final GlobalKey _firstDocumentKey = GlobalKey();
  
  // ShowCaseWidget内のBuildContextを保存
  BuildContext? _showcaseContext;

  // 安全な型変換メソッド
  Map<String, dynamic> _convertToMap(dynamic data) {
    if (data == null) {
      return <String, dynamic>{};
    }
    
    if (data is Map<String, dynamic>) {
      return data;
    }
    
    if (data is Map) {
      final result = <String, dynamic>{};
      data.forEach((key, value) {
        result[key.toString()] = _convertValue(value);
      });
      return result;
    }
    
    // その他の場合は空のマップを返す
    return <String, dynamic>{};
  }

  // ネストされた値の変換メソッド
  dynamic _convertValue(dynamic value) {
    if (value == null) {
      return null;
    }
    
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, val) {
        result[key.toString()] = _convertValue(val);
      });
      return result;
    }
    
    if (value is List) {
      return value.map((item) => _convertValue(item)).toList();
    }
    
    return value;
  }

  @override
  void dispose() {
    // バナー広告を解除
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() async {
    _bannerAd = await AdMobService.createBannerAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {
            _isBannerAdReady = true;
          });
        }
      },
      onAdFailedToLoad: (error) {
        print('バナー広告の読み込みに失敗: ${error.message}');
      },
    );
    
    // プランチェックの結果、広告が作成された場合のみ読み込み
    if (_bannerAd != null) {
      _bannerAd!.load();
    }
  }

  // 外部からファイル選択ダイアログを開くためのメソッド
  void showFileSelectionDialog() {
    _showFileSelectionDialog();
  }
  
  // 外部からチュートリアルを開始するメソッド
  void startDocumentTutorial() {
    _checkAndShowTutorial();
  }
  
  // チュートリアルを表示するかチェック
  Future<void> _checkAndShowTutorial() async {
    // showcaseContextがない場合は表示しない
    if (_showcaseContext == null) return;
    
    // ファイルがない場合は表示しない
    if (_uploadedFiles.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial = prefs.getBool('documents_page_tutorial_shown') ?? false;
    
    if (!hasShownTutorial && mounted) {
      // 最初のドキュメントをハイライト
      ShowCaseWidget.of(_showcaseContext!).startShowCase([_firstDocumentKey]);
      // フラグを保存
      await prefs.setBool('documents_page_tutorial_shown', true);
    }
  }
  
  @override
  void initState() {
    super.initState();
    _loadUploadedFiles();
    _loadBannerAd();
  }

  Future<void> _loadUploadedFiles() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Firestoreからファイル一覧を取得
      final QuerySnapshot result = await _firestore
          .collection('user_documents')
          .where('user_id', isEqualTo: user.uid)
          .orderBy('created_at', descending: true)
          .get();

      List<DocumentFile> files = [];

      for (final doc in result.docs) {
        final data = doc.data() as Map<String, dynamic>;
        files.add(DocumentFile.fromMap(data, doc.id));
      }

      setState(() {
        _uploadedFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('ファイル一覧の読み込みに失敗しました: $e');
    }
  }

  Future<void> _showFileSelectionDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return FileSelectionBottomSheet(
          onFileSelected: _selectFile,
          onTextSelected: _showTextInputDialog,
          onDocumentScanSelected: _scanDocument,
          onPhotosSelected: _selectPhotos,
          onTakePhotosSelected: _takePhotos,
        );
      },
    );
  }



  Future<void> _selectFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'mp3', 'wav', 'm4a', 'mp4', 'mov', 'mpg', 'mpeg'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        if (file.path != null) {
          final fileType = _getFileType(file.name);
          
          // 音声ファイルの場合は直接アップロード（文字起こしタイプ選択をスキップ）
          if (_isAudioFile(fileType)) {
            _uploadFile(file.path!, file.name, 'audio_full');
          } else if (_isVideoFile(fileType)) {
            _uploadFile(file.path!, file.name, 'video_full');
          } else if (fileType == 'pdf') {
            // PDFページ数チェック
            final doc = await PdfDocument.openFile(file.path!);
            final pageCount = doc.pageCount;
            await doc.dispose();
            if (pageCount > 4) {
              _showMessage('❌ PDFは4ページ以内のファイルのみ対応しています');
              return;
            }
            // PDFの場合は文字起こしタイプ選択
            _showTranscriptionTypeDialog(file.path!, file.name);
          }
        }
      }
    } catch (e) {
      _showMessage('ファイルの選択に失敗しました');
    }
  }

  // 書類スキャン機能
  Future<void> _scanDocument() async {
    try {
      _showMessage('📷 書類をスキャンしています...', isSuccess: true);
      
      final pdfPath = await FlutterDocScanner().getScannedDocumentAsPdf(page: 5);
      if (pdfPath != null && pdfPath.isNotEmpty) {
        final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File(pdfPath);
        
        if (await file.exists()) {
          // スキャンしたPDFを文字起こしタイプ選択ダイアログに送る
          _showTranscriptionTypeDialog(pdfPath, fileName);
          _showMessage('✅ PDFとして書類をスキャンしました', isSuccess: true);
        } else {
          _showMessage('❌ スキャンしたファイルが見つかりません');
        }
      } else {
        _showMessage('❌ 書類のスキャンがキャンセルされました');
      }
    } catch (e) {
      _showMessage('❌ 書類スキャンエラー: $e');
    }
  }

  // 写真選択機能
  Future<void> _selectPhotos() async {
    try {
      _showMessage('📸 写真を選択してください...', isSuccess: true);
      
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(
        imageQuality: 85, // 画質を調整してファイルサイズを制御
        maxWidth: 2048,   // 最大幅を制限
        maxHeight: 2048,  // 最大高さを制限
      );
      
      if (images.isNotEmpty) {
        if (images.length > 4) {
          _showMessage('❌ 最大4枚まで選択可能です。4枚以内で選択してください');
          return;
        }
        _uploadImages(images);
      } else {
        _showMessage('❌ 写真の選択がキャンセルされました');
      }
    } catch (e) {
      _showMessage('❌ 写真選択エラー: $e');
    }
  }

  // 写真撮影機能（最大4枚）
  Future<void> _takePhotos() async {
    try {
      List<XFile> takenImages = [];
      final ImagePicker picker = ImagePicker();
      for (int i = 0; i < 4; i++) {
        final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
        if (photo != null) {
          takenImages.add(photo);
          if (i < 3) {
            // 追加撮影するか確認
            final bool? takeMore = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('写真を追加撮影しますか？'),
                content: Text('現在${takenImages.length}枚撮影済み（最大4枚）'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('やめる'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('続けて撮影'),
                  ),
                ],
              ),
            );
            if (takeMore != true) break;
          }
        } else {
          // キャンセル時
          break;
        }
      }
      if (takenImages.isNotEmpty) {
        _uploadImages(takenImages);
      } else {
        _showMessage('❌ 写真撮影がキャンセルされました');
      }
    } catch (e) {
      _showMessage('❌ 写真撮影エラー: $e');
    }
  }

  Future<void> _showTextInputDialog() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TextInputPage(
          onTextSubmitted: _addTextDocument,
        ),
      ),
    );
  }

  Future<void> _addTextDocument(String title, String text) async {
    try {
      final user = _auth.currentUser;
      
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }

      // Firestoreにテキストドキュメントを保存
      final docRef = await _firestore.collection('user_documents').add({
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'type': 'text',
        'title': title,
        'transcription': text, // テキストを直接transcriptionフィールドに保存
        'status': '未解析',
      });
      
      _showMessage('✅ テキストを追加しました', isSuccess: true);
      
      // ファイル一覧を再読み込み
      _loadUploadedFiles();

      // 自動的にSavor解析を開始
      _callSavorFunction(docRef.id);

    } catch (e) {
      _showMessage('❌ テキストの追加に失敗しました: $e');
    }
  }

  Future<void> _showTranscriptionTypeDialog(String filePath, String fileName) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TranscriptionTypePage(
          fileName: fileName,
          onTranscriptionTypeSelected: (transcriptionType) {
            _uploadFile(filePath, fileName, transcriptionType);
          },
        ),
      ),
    );
  }

  Future<void> _uploadImages(List<XFile> images) async {
    if (_isUploading) return;
    
    setState(() {
      _isUploading = true;
    });

    try {
      final user = _auth.currentUser;
      
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }

      List<String> imagePaths = [];
      
      // 各画像をStorageにアップロード
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        _showMessage('📤 画像 ${i + 1}/${images.length} をアップロード中...', isSuccess: true);
        
        final file = File(image.path);
        final fileExists = await file.exists();
        
        if (!fileExists) {
          _showMessage('画像ファイルが見つかりません: ${image.name}');
          continue;
        }

        final uploadFileName = '${DateTime.now().millisecondsSinceEpoch}_${i}_${image.name}';
        
        // シンプルなパス指定でStorage参照を作成
        final ref = _storage.ref('documents/${user.uid}/$uploadFileName');

        final uploadTask = ref.putFile(file);
        await uploadTask;
        
        // GSパスを取得
        final gsPath = 'gs://${ref.bucket}/${ref.fullPath}';
        imagePaths.add(gsPath);
      }
      
      if (imagePaths.isEmpty) {
        _showMessage('❌ アップロード可能な画像がありませんでした');
        return;
      }
      
      // Firestoreにメタデータを保存
      final fileTitle = '画像${images.length}枚 ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}';
      
      final docRef = await _firestore.collection('user_documents').add({
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'type': 'image',
        'title': fileTitle,
        'image_paths': imagePaths,
        'status': '未解析',
      });
      
      _showMessage('✅ ${images.length}枚の画像をアップロードしました', isSuccess: true);
      
      // 画像ファイルの場合は自動的に文字起こし処理を開始
      _callImageTranscribeFunction(docRef.id);
      
      // ファイル一覧を再読み込み
      _loadUploadedFiles();

    } catch (e) {
      String errorMessage = '❌ アップロードに失敗しました\n';
      
      if (e.toString().contains('permission-denied')) {
        errorMessage += '原因: 権限が不足しています';
      } else if (e.toString().contains('unauthorized')) {
        errorMessage += '原因: 認証に失敗しました';
      } else if (e.toString().contains('network')) {
        errorMessage += '原因: ネットワークエラー';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage += '原因: 不正な引数です';
      } else {
        errorMessage += '詳細: ${e.toString()}';
      }
      
      _showMessage(errorMessage);
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _uploadFile(String filePath, String fileName, String transcriptionType) async {
    if (_isUploading) return;
    
    setState(() {
      _isUploading = true;
    });

    try {
      final user = _auth.currentUser;
      
      if (user == null) {
        _showMessage('ログインが必要です');
        return;
      }

      final file = File(filePath);
      final fileExists = await file.exists();
      
      if (!fileExists) {
        _showMessage('ファイルが見つかりません');
        return;
      }

      final uploadFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      // シンプルなパス指定でStorage参照を作成
      final ref = _storage.ref('documents/${user.uid}/$uploadFileName');

      final uploadTask = ref.putFile(file);
      await uploadTask;
      
      // Firestoreにメタデータを保存
      final gsPath = 'gs://${ref.bucket}/${ref.fullPath}';
      final fileType = _getFileType(fileName);
      final fileTitle = _getFileTitle(fileName);
      
      // ファイルタイプに応じてtypeを設定
      String documentType;
      if (_isAudioFile(fileType)) {
        documentType = 'audio';
      } else if (_isVideoFile(fileType)) {
        documentType = 'video';
      } else if (fileType == 'pdf') {
        documentType = 'file';
      } else {
        documentType = 'file'; // デフォルト
      }
      
      final docRef = await _firestore.collection('user_documents').add({
        'user_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'path': gsPath,
        'type': documentType,
        'title': fileTitle,
        'request': transcriptionType,
        'status': '未解析',
      });
      
      
      _showMessage('✅ $fileName をアップロードしました', isSuccess: true);
      
      // ファイルタイプに応じて文字起こし処理を開始
      if (fileType == 'pdf') {
        _callTranscribeFunction(docRef.id);
      } else if (_isAudioFile(fileType)) {
        _callAudioTranscribeFunction(docRef.id);
      } else if (_isVideoFile(fileType)) {
        _callVideoTranscribeFunction(docRef.id);
      }
      
      // ファイル一覧を再読み込み
      _loadUploadedFiles();

    } catch (e) {
      String errorMessage = '❌ アップロードに失敗しました\n';
      
      if (e.toString().contains('permission-denied')) {
        errorMessage += '原因: 権限が不足しています';
      } else if (e.toString().contains('unauthorized')) {
        errorMessage += '原因: 認証に失敗しました';
      } else if (e.toString().contains('network')) {
        errorMessage += '原因: ネットワークエラー';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage += '原因: 不正な引数です';
      } else {
        errorMessage += '詳細: ${e.toString()}';
      }
      
      _showMessage(errorMessage);
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _deleteFile(DocumentFile file) async {
    try {
      // audioファイルの場合のみStorageからも削除
      if (file.type == 'audio') {
        try {
          final ref = _storage.refFromURL(file.path);
          await ref.delete();
        } catch (storageError) {
          // Storageの削除に失敗してもFirestoreの削除は続行
          print('Storage削除に失敗しましたが、処理を続行します: $storageError');
        }
      }
      
      // Firestoreからドキュメントを削除
      await _firestore.collection('user_documents').doc(file.id).delete();
      
      _showMessage('ファイルを削除しました', isSuccess: true);
      _loadUploadedFiles(); // ファイル一覧を再読み込み
    } catch (e) {
      _showMessage('ファイルの削除に失敗しました: $e');
    }
  }

  Future<void> _showTranscriptionDetails(DocumentFile file) async {
    // Firestoreから最新の文字起こし情報を取得
    try {
      final docSnapshot = await _firestore.collection('user_documents').doc(file.id).get();
      final data = docSnapshot.data();
      
      if (data == null) {
        _showMessage('ドキュメント情報が見つかりません');
        return;
      }
      
      final String? transcription = data['transcription'] as String?;
      
      if (transcription == null) {
        _showMessage('文字起こしがまだ完了していません');
        return;
      }
      
      _showTranscriptionEditDialog(file.id, file.title, transcription);
      
    } catch (e) {
      _showMessage('文字起こし情報の取得に失敗しました: $e');
    }
  }

  Future<void> _showSavorResultsDetails(DocumentFile file) async {
    // Firestoreから最新のSavor解析結果を取得
    try {
      // documents_savor_resultsコレクションから取得
      final savorSnapshot = await _firestore.collection('documents_savor_results').doc(file.id).get();
      final savorData = savorSnapshot.data();
      
      if (savorData == null) {
        _showMessage('Savor解析がまだ完了していません');
        return;
      }
      
      final Map<String, dynamic> savorResult = _convertToMap(savorData);
      
      // 新しいページに遷移
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SavorResultPage(
              documentId: file.id,
              title: file.title,
              savorResult: savorResult,
            ),
          ),
        );
      }
      
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // 所有者であれば、文字起こし編集ページに誘導して解析を促す
        try {
          final doc = await _firestore.collection('user_documents').doc(file.id).get();
          final data = doc.data();
          final uid = _auth.currentUser?.uid;
          if (doc.exists && data != null && data['user_id'] == uid) {
            final String title = data['title'] ?? file.title;
            final String initialTranscription = (data['transcription'] as String?) ?? '';
            _showTranscriptionEditDialog(file.id, title, initialTranscription);
            return;
          }
        } catch (_) {
          // 続行してエラーメッセージ表示
        }
      }
      _showMessage('Savor解析結果の取得に失敗しました: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Savor解析結果の取得に失敗しました: $e');
    }
  }

  void _showTranscriptionEditDialog(String documentId, String title, String initialTranscription) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TranscriptionEditPage(
          documentId: documentId,
          title: title,
          initialTranscription: initialTranscription,
          onTranscriptionSaved: _saveTranscription,
        ),
      ),
    );
  }

  Future<void> _saveTranscription(String documentId, String transcription) async {
    try {
      await _firestore.collection('user_documents').doc(documentId).update({
        'transcription': transcription,
      });                    
    } catch (e) {
      _showMessage('保存に失敗しました: $e');
    }
  }

  Future<void> _editFileTitle(DocumentFile file, String newTitle) async {
    try {
      await _firestore
          .collection('user_documents')
          .doc(file.id)
          .update({
        'title': newTitle,
      });
      
      _showMessage('タイトルを更新しました', isSuccess: true);
      _loadUploadedFiles(); // ファイル一覧を再読み込み
    } catch (e) {
      _showMessage('タイトルの更新に失敗しました: $e');
    }
  }



  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch ('.$extension') {
      case '.pdf':
        return 'pdf';
      case '.mp3':
        return 'mp3';
      case '.wav':
        return 'wav';
      case '.m4a':
        return 'm4a';
      case '.mp4':
        return 'mp4';
      case '.mov':
        return 'mov';
      case '.mpg':
        return 'mpg';
      case '.mpeg':
        return 'mpeg';
      case '.jpg':
      case '.jpeg':
        return 'jpg';
      case '.png':
        return 'png';
      default:
        return 'unknown';
    }
  }

  String _getFileTitle(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  // 音声ファイルかどうかを判定するヘルパーメソッド
  bool _isAudioFile(String fileType) {
    const audioTypes = [
      'mp3', 'wav', 'm4a'
    ];
    return audioTypes.contains(fileType);
  }

  // 動画ファイルかどうかを判定するヘルパーメソッド
  bool _isVideoFile(String fileType) {
    const videoTypes = [
      'mp4', 'mov', 'mpg', 'mpeg'
    ];
    return videoTypes.contains(fileType);
  }

  Future<void> _callTranscribeFunction(String documentId) async {
    try {
      _showMessage('📄 ドキュメントの文字起こしを開始しています...', isSuccess: true);
      
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('transcribeDocument');
      
      final result = await callable.call({
        'documentId': documentId,
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        _showMessage('✅ ドキュメントの文字起こしが完了しました', isSuccess: true);
        
        // ファイル一覧を再読み込みして最新状態を反映
        _loadUploadedFiles();
        
        // 文字起こし結果を自動的に表示
        final String transcription = responseData['transcription'] ?? '';
        if (transcription.isNotEmpty) {
          // ドキュメントのタイトルを取得するためにFirestoreから情報を取得
          try {
            final docSnapshot = await _firestore.collection('user_documents').doc(documentId).get();
            final docData = docSnapshot.data();
            final String title = docData?['title'] ?? 'Unknown Document';
            
            // 文字起こし編集ダイアログを表示
            _showTranscriptionEditDialog(documentId, title, transcription);
          } catch (e) {
            // タイトル取得に失敗した場合でも、デフォルトタイトルで表示
            _showTranscriptionEditDialog(documentId, 'Document', transcription);
          }
        }
      } else {
        _showMessage('❌ ドキュメント処理に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ ドキュメント処理に失敗しました';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = '❌ 認証が必要です。ログインしてください。';
          break;
        case 'permission-denied':
          errorMessage = '❌ このドキュメントにアクセスする権限がありません。';
          break;
        case 'not-found':
          errorMessage = '❌ ドキュメントまたはファイルが見つかりません。';
          break;
        case 'failed-precondition':
          errorMessage = '❌ ドキュメントパスが見つかりません。';
          break;
        default:
          errorMessage = '❌ エラーが発生しました: ${e.message}';
          break;
      }
      _showMessage(errorMessage);
    } catch (e) {
      _showMessage('❌ ドキュメント処理でエラーが発生しました: $e');
    }
  }

  Future<void> _callAudioTranscribeFunction(String documentId) async {
    try {
      _showMessage('🎵 音声ファイルの文字起こしを開始しています...', isSuccess: true);
      
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('transcribeAudio');
      
      final result = await callable.call({
        'documentId': documentId,
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        _showMessage('✅ 音声ファイルの文字起こしが完了しました', isSuccess: true);
        
        // ファイル一覧を再読み込みして最新状態を反映
        _loadUploadedFiles();
        
        // 文字起こし結果を自動的に表示
        final String transcription = responseData['transcription'] ?? '';
        if (transcription.isNotEmpty) {
          // ドキュメントのタイトルを取得するためにFirestoreから情報を取得
          try {
            final docSnapshot = await _firestore.collection('user_documents').doc(documentId).get();
            final docData = docSnapshot.data();
            final String title = docData?['title'] ?? 'Unknown Document';
            
            // 文字起こし編集ダイアログを表示
            _showTranscriptionEditDialog(documentId, title, transcription);
          } catch (e) {
            // タイトル取得に失敗した場合でも、デフォルトタイトルで表示
            _showTranscriptionEditDialog(documentId, 'Document', transcription);
          }
        }
      } else {
        _showMessage('❌ 音声ファイル処理に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ 音声ファイル処理に失敗しました';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = '❌ 認証が必要です。ログインしてください。';
          break;
        case 'permission-denied':
          errorMessage = '❌ このドキュメントにアクセスする権限がありません。';
          break;
        case 'not-found':
          errorMessage = '❌ 音声ファイルが見つかりません。';
          break;
        case 'invalid-argument':
          errorMessage = '❌ 音声ファイルが大きすぎます（20MB以下にしてください）。';
          break;
        default:
          errorMessage = '❌ エラーが発生しました: ${e.message}';
          break;
      }
      _showMessage(errorMessage);
    } catch (e) {
      _showMessage('❌ 音声ファイル処理でエラーが発生しました: $e');
    }
  }

  Future<void> _callImageTranscribeFunction(String documentId) async {
    try {
      _showMessage('🖼️ 画像の文字起こしを開始しています...', isSuccess: true);
      
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('transcribeImages');
      
      final result = await callable.call({
        'documentId': documentId,
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        final int processedImages = responseData['processedImages'] ?? 0;
        _showMessage('✅ ${processedImages}枚の画像の文字起こしが完了しました', isSuccess: true);
        
        // ファイル一覧を再読み込みして最新状態を反映
        _loadUploadedFiles();
        
        // 文字起こし結果を自動的に表示
        final String transcription = responseData['transcription'] ?? '';
        if (transcription.isNotEmpty) {
          // ドキュメントのタイトルを取得するためにFirestoreから情報を取得
          try {
            final docSnapshot = await _firestore.collection('user_documents').doc(documentId).get();
            final docData = docSnapshot.data();
            final String title = docData?['title'] ?? 'Unknown Document';
            
            // 文字起こし編集ダイアログを表示
            _showTranscriptionEditDialog(documentId, title, transcription);
          } catch (e) {
            // タイトル取得に失敗した場合でも、デフォルトタイトルで表示
            _showTranscriptionEditDialog(documentId, 'Document', transcription);
          }
        }
      } else {
        _showMessage('❌ 画像処理に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ 画像処理に失敗しました';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = '❌ 認証が必要です。ログインしてください。';
          break;
        case 'permission-denied':
          errorMessage = '❌ このドキュメントにアクセスする権限がありません。';
          break;
        case 'not-found':
          errorMessage = '❌ 画像ファイルが見つかりません。';
          break;
        case 'failed-precondition':
          errorMessage = '❌ 有効な画像ファイルが見つかりません。';
          break;
        default:
          errorMessage = '❌ エラーが発生しました: ${e.message}';
          break;
      }
      _showMessage(errorMessage);
    } catch (e) {
      _showMessage('❌ 画像処理でエラーが発生しました: $e');
    }
  }

  Future<void> _callVideoTranscribeFunction(String documentId) async {
    try {
      _showMessage('🎬 動画の文字起こしを開始しています...', isSuccess: true);
      
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('transcribeVideo');
      
      final result = await callable.call({
        'documentId': documentId,
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        _showMessage('✅ 動画の文字起こしが完了しました', isSuccess: true);
        
        // ファイル一覧を再読み込みして最新状態を反映
        _loadUploadedFiles();
        
        // 文字起こし結果を自動的に表示
        final String transcription = responseData['transcription'] ?? '';
        if (transcription.isNotEmpty) {
          // ドキュメントのタイトルを取得するためにFirestoreから情報を取得
          try {
            final docSnapshot = await _firestore.collection('user_documents').doc(documentId).get();
            final docData = docSnapshot.data();
            final String title = docData?['title'] ?? 'Unknown Document';
            
            // 文字起こし編集ダイアログを表示
            _showTranscriptionEditDialog(documentId, title, transcription);
          } catch (e) {
            // タイトル取得に失敗した場合でも、デフォルトタイトルで表示
            _showTranscriptionEditDialog(documentId, 'Document', transcription);
          }
        }
      } else {
        _showMessage('❌ 動画処理に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ 動画処理に失敗しました';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = '❌ 認証が必要です。ログインしてください。';
          break;
        case 'permission-denied':
          errorMessage = '❌ このドキュメントにアクセスする権限がありません。';
          break;
        case 'not-found':
          errorMessage = '❌ 動画ファイルが見つかりません。';
          break;
        case 'invalid-argument':
          errorMessage = '❌ 動画ファイルが大きすぎます（50MB以下にしてください）。';
          break;
        default:
          errorMessage = '❌ エラーが発生しました: ${e.message}';
          break;
      }
      _showMessage(errorMessage);
    } catch (e) {
      _showMessage('❌ 動画処理でエラーが発生しました: $e');
    }
  }

  Future<void> _callSavorFunction(String documentId) async {
    try {
      // インタースティシャル広告を表示（iOSでのみ実行）
      _showInterstitialAd();
      
      // HTTPS Callable Functions を呼び出し
      final HttpsCallable callable = _functions.httpsCallable('savorDocument');
      
      final result = await callable.call({
        'documentId': documentId,
      });
      
      // 安全な型キャスト
      final responseData = _convertToMap(result.data);
      
      if (responseData['success'] == true) {
        _showMessage('✅ ドキュメントの解析が完了しました', isSuccess: true);
        
        // ファイル一覧を再読み込みして最新状態を反映
        _loadUploadedFiles();
        
        // 解析結果を自動的に表示するために、documents_savor_resultsから取得
        try {
          final docSnapshot = await _firestore.collection('user_documents').doc(documentId).get();
          final docData = docSnapshot.data();
          final String title = docData?['title'] ?? 'Unknown Document';
          
          // documents_savor_resultsから解析結果を取得
          final savorSnapshot = await _firestore.collection('documents_savor_results').doc(documentId).get();
          final savorData = savorSnapshot.data();
          
          if (mounted && savorData != null) {
            final Map<String, dynamic> result = _convertToMap(savorData);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SavorResultPage(
                  documentId: documentId,
                  title: title,
                  savorResult: result,
                ),
              ),
            );
          }
        } catch (e) {
          // エラーの場合
          _showMessage('❌ 解析結果の取得に失敗しました: $e');
        }
      } else {
        _showMessage('❌ ドキュメント解析に失敗しました: ${responseData['error'] ?? 'Unknown error'}');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage = '❌ ドキュメント解析に失敗しました';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = '❌ 認証が必要です。ログインしてください。';
          break;
        case 'permission-denied':
          errorMessage = '❌ このドキュメントにアクセスする権限がありません。';
          break;
        case 'failed-precondition':
          if (e.message?.contains('not English') == true) {
            _showNotEnglishDialog();
            return;
          } else {
            errorMessage = '❌ 文字起こしが見つかりません。先に文字起こしを実行してください。';
          }
          break;
        case 'resource-exhausted':
          errorMessage = '❌ Gemが不足しています。';
          break;
        default:
          errorMessage = '❌ エラーが発生しました: ${e.message}';
          break;
      }
      _showMessage(errorMessage);
    } catch (e) {
      _showMessage('❌ ドキュメント解析でエラーが発生しました: $e');
    }
  }

  void _showInterstitialAd() async {
    await AdMobService.createInterstitialAd(
      onAdLoaded: (InterstitialAd ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            print('インタースティシャルの表示に失敗: $error');
          },
        );
        ad.show();
      },
      onAdFailedToLoad: (LoadAdError error) {
        print('インタースティシャルの読み込みに失敗: ${error.message}');
      },
    );
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showNotEnglishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.language, color: Colors.red[600]),
              const SizedBox(width: 8),
              const Text('英文ではありません'),
            ],
          ),
          content: const Text('入力されたテキストが英文として認識されませんでした。\n\n英語の文書のみ解析可能です。文字起こしやテキストを確認して、英語の内容に修正してください。'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('了解'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) {
        // ShowCaseWidget内のcontextを保存
        _showcaseContext = context;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          bottomNavigationBar: (_isBannerAdReady && _bannerAd != null)
              ? SafeArea(
                  child: Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                )
              : null,
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _uploadedFiles.isEmpty
                  ? const EmptyStateWidget()
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
                      itemCount: _uploadedFiles.length,
                      itemBuilder: (context, index) {
                        final file = _uploadedFiles[index];
                        final isFirstDocument = index == 0;
                        
                        Widget documentCard = Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                          child: DocumentFileCard(
                            file: file,
                            onFileDeleted: _deleteFile,
                            onTranscriptionView: _showTranscriptionDetails,
                            onSavorAnalyze: _callSavorFunction,
                            onSavorResultView: _showSavorResultsDetails,
                            onTitleEdit: _editFileTitle,
                          ),
                        );
                        
                        // 最初のドキュメントにはShowcaseを追加
                        if (isFirstDocument) {
                          return Showcase(
                            key: _firstDocumentKey,
                            title: 'ドキュメントをタップ',
                            description: 'チュートリアル用の英文で使い方を覚えよう✨',
                            targetPadding: const EdgeInsets.all(8),
                            child: documentCard,
                          );
                        }
                        
                        return documentCard;
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
} 