import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プライバシーポリシー'),
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
              'プライバシーポリシー',
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
              '1. 個人情報の収集',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、LingoSavor（以下「本サービス」）の提供にあたり、以下の個人情報を収集いたします：\n'
              '• アカウント情報（メールアドレス、ユーザー名等）\n'
              '• 学習データ（学習履歴、進捗状況等）\n'
              '• 利用ログ（アクセス日時、利用機能等）\n'
              '• デバイス情報（デバイスID、OS情報等）',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '2. 個人情報の利用目的',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '収集した個人情報は、以下の目的で利用いたします：\n'
              '• 本サービスの提供・運営\n'
              '• ユーザーサポートの提供\n'
              '• サービスの改善・開発\n'
              '• セキュリティの確保\n'
              '• 法令に基づく対応',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '3. 個人情報の管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、個人情報の正確性及び安全性を確保するために、セキュリティの向上及び従業員の教育等の必要な措置を講じ、個人情報の漏洩、滅失又はき損の防止その他の個人情報の適切な管理を行います。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '4. 個人情報の第三者提供',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、以下の場合を除き、個人情報を第三者に提供いたしません：\n'
              '• ユーザーの同意がある場合\n'
              '• 法令に基づき開示することが必要である場合\n'
              '• 人の生命、身体又は財産の保護のために必要な場合\n'
              '• 公衆衛生の向上又は児童の健全な育成の推進のために特に必要な場合',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '5. 個人情報の開示・訂正・利用停止',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'ユーザーは、当社に対して、ご自身の個人情報の開示、訂正、利用停止を求めることができます。これらの請求については、お問い合わせフォームからご連絡ください。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '6. プライバシーポリシーの変更',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '当社は、必要に応じて本プライバシーポリシーを変更することができます。変更後のプライバシーポリシーは、本サービス上で公表された時点から効力を生じるものとします。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '7. お問い合わせ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '本プライバシーポリシーに関するお問い合わせは、お問い合わせフォームからご連絡ください。',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 