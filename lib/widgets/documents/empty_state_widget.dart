import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // アイコン
              Icon(
                Icons.school, 
                size: 64, 
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              
              // タイトル
              Text(
                'LingoSavorの使い方',
                style: TextStyle(
                  fontSize: 24, 
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // 説明文
              Text(
                'LingoSavorはあなたが学んだ英文をAIの力で解析し\n効率的な英語学習をサポートします',
                style: TextStyle(
                  fontSize: 14, 
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // ステップガイド
              _buildStepItem(
                context,
                stepNumber: '1',
                title: '英文をアップロード',
                description: '下の＋ボタンから英文をアップロード',
                icon: Icons.add_circle_outline,
              ),
              const SizedBox(height: 16),
              
              _buildStepItem(
                context,
                stepNumber: '2',
                title: '解析完了を待つ',
                description: '解析中が解析完了になったら、タップして学習開始！',
                icon: Icons.analytics_outlined,
              ),
              const SizedBox(height: 16),
              
              _buildStepItem(
                context,
                stepNumber: '3',
                title: '学習を開始',
                description: '分からない単語をタップして保存！\n「選択」ボタンで文法がわからないところを囲ってAIに質問しよう！',
                icon: Icons.touch_app_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required String stepNumber,
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // ステップ番号
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                stepNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // アイコン
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          
          // テキスト
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

