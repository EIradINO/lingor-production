import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('利用規約'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '利用規約',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              '最終更新日: 2025年8月',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 24),
            Text(
              '1. サービスの利用',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'LingoSavor（以下「本サービス」）は、言語学習を支援するためのアプリケーションです。本サービスを利用する際は、本利用規約に従っていただく必要があります。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '2. ユーザーの責任',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'ユーザーは、本サービスの利用にあたり、以下の事項を遵守するものとします：\n'
              '• 法令の遵守\n'
              '• 他者の権利の尊重\n'
              '• 適切な利用目的での使用\n'
              '• アカウント情報の適切な管理',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '3. 禁止事項',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '以下の行為は禁止されています：\n'
              '• 本サービスの運営を妨害する行為\n'
              '• 他者の個人情報を無断で収集・利用する行為\n'
              '• 本サービスの著作権等の知的財産権を侵害する行為\n'
              '• その他、本サービスの利用目的に反する行為',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '4. サービスの変更・停止',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、事前の通知なく、本サービスの内容を変更し、または本サービスの提供を停止することができるものとします。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '5. 免責事項',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、本サービスの利用により生じた損害について、一切の責任を負わないものとします。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '6. 利用規約の変更',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、必要に応じて本利用規約を変更することができるものとします。変更後の利用規約は、本サービス上で公表された時点から効力を生じるものとします。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '7. 準拠法・管轄裁判所',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '本利用規約の解釈にあたっては、日本法を準拠法とします。本利用規約に関して紛争が生じた場合には、東京地方裁判所を第一審の専属管轄裁判所とします。',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 