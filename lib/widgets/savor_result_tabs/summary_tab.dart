import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class SummaryTab extends StatelessWidget {
  final Map<String, dynamic> savorResult;

  const SummaryTab({
    super.key,
    required this.savorResult,
  });

  String _getSafeStringValue(dynamic value, String defaultValue) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: _getSafeStringValue(savorResult['summary'], '概要情報がありません'),
      padding: const EdgeInsets.all(4),
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 16, height: 1.6),
        h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
} 