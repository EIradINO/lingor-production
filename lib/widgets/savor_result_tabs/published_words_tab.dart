import 'package:flutter/material.dart';

class PublishedWordsTab extends StatelessWidget {
  final Map<String, dynamic> savorResult;

  const PublishedWordsTab({
    super.key,
    required this.savorResult,
  });

  @override
  Widget build(BuildContext context) {
    final matchedWords = savorResult['matched_published_words'] as Map<String, dynamic>? ?? {};

    if (matchedWords.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '市販の単語帳に収録されている単語は\nありませんでした',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // 単語をアルファベット順にソート
    final sortedWords = matchedWords.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '${sortedWords.length}個の単語が市販の単語帳に収録されています',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sortedWords.length,
            itemBuilder: (context, index) {
              final word = sortedWords[index];
              final wordData = matchedWords[word] as Map<String, dynamic>;
              return _buildWordCard(context, word, wordData);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWordCard(BuildContext context, String word, Map<String, dynamic> wordData) {
    final appearances = (wordData['appearances'] as List<dynamic>?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 単語
            Text(
              word,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 出現情報リスト
            ...appearances.map((appearance) => _buildAppearanceItem(context, appearance as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceItem(BuildContext context, Map<String, dynamic> appearance) {
    final wordlistTitle = appearance['wordlistTitle'] as String? ?? '';
    final number = appearance['number'];
    final page = appearance['page'];
    final type = appearance['type'] as String? ?? 'main';
    final parentWord = appearance['parentWord'] as String?;

    // 番号・ページ情報の構築
    String locationInfo = '';
    if (number != null && page != null) {
      locationInfo = 'No.$number / p.$page';
    } else if (number != null) {
      locationInfo = 'No.$number';
    } else if (page != null) {
      locationInfo = 'p.$page';
    }

    // タイプに応じたラベル
    String typeLabel = '';
    Color typeColor = Colors.grey;
    if (type == 'derivative' && parentWord != null) {
      typeLabel = '派生語（$parentWord）';
      typeColor = Colors.blue;
    } else if (type == 'synonym' && parentWord != null) {
      typeLabel = '類義語（$parentWord）';
      typeColor = Colors.green;
    } else if (type == 'antonym' && parentWord != null) {
      typeLabel = '反意語（$parentWord）';
      typeColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // 単語帳アイコン
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.menu_book,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wordlistTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (locationInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    locationInfo,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                if (typeLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: typeColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
