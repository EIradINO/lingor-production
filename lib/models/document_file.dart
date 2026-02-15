import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentFile {
  final String id;
  final String title;
  final String type;
  final String path;
  final DateTime? createdAt;
  final String? transcription;
  final String? request;
  final String? status;

  const DocumentFile({
    required this.id,
    required this.title,
    required this.type,
    required this.path,
    this.createdAt,
    this.transcription,
    this.request,
    this.status,
  });

  factory DocumentFile.fromMap(Map<String, dynamic> map, String documentId) {
    return DocumentFile(
      id: documentId,
      title: map['title'] ?? 'Unknown',
      type: map['type'] ?? 'unknown',
      path: map['path'] ?? '',
      createdAt: map['created_at'] != null 
          ? (map['created_at'] as Timestamp).toDate() 
          : null,
      transcription: map['transcription'] as String?,
      request: map['request'] as String?,
      status: map['status'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      'path': path,
      'created_at': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'transcription': transcription,
      'request': request,
      'status': status,
    };
  }

  DocumentFile copyWith({
    String? id,
    String? title,
    String? type,
    String? path,
    DateTime? createdAt,
    String? transcription,
    String? request,
    String? status,
  }) {
    return DocumentFile(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      transcription: transcription ?? this.transcription,
      request: request ?? this.request,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'DocumentFile(id: $id, title: $title, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DocumentFile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
} 