# LingoSavor - AI英語学習プラットフォーム

## 概要

LingoSavorは、Google Vertex AI（Gemini）とFirebaseを活用した**AI駆動型の英語学習プラットフォーム**です。ドキュメント（PDF、画像、動画）から英文を自動抽出し、単語学習、文法問題、リーディング・リスニング問題を生成する革新的な学習アプリケーションです。

- **バージョン**: 1.10.0
- **対応プラットフォーム**: iOS, Android, Web, macOS, Windows, Linux
- **技術スタック**: Flutter + Firebase + Vertex AI (Gemini)

---

## 主要機能

### 1. SAVOR（Smart Analysis and Vocabulary Optimization Retrieval）

アプリのコア機能であるドキュメント解析システム。

- **ドキュメントアップロード**: PDF、画像、動画に対応
- **自動文字起こし**: AIによる高精度なテキスト抽出
- **単語抽出**: 重要単語の自動識別・抽出
- **意味生成**: Gemini AIによる詳細な単語解説
- **基本形変換**: 活用形を原形に統一
- **文脈役割分析**: 文章内での単語の役割を解説

### 2. 日次学習タスク

毎日の学習を習慣化するためのタスクシステム。

| タスク種別 | 内容 |
|-----------|------|
| 文法問題 | 単語の意味を選択肢から選ぶ問題 |
| リーディング | テキスト読解と内容理解問題 |
| リスニング | 音声付きリスニング問題 |

### 3. 単語学習機能

- 学習単語の保存・管理
- カスタムワードリストの作成・編集
- 「炎マーク」機能で重要単語をハイライト
- 辞書検索・単語詳細表示
- 復習機能

### 4. AIチャットボット

- Gemini統合のAI会話機能
- 英語学習に関する質問対応
- 会話練習サポート
- スレッド（ルーム）管理

### 5. メディア処理

- PDF → テキスト抽出
- 画像（スクリーンショット等）→ OCR
- 動画 → 音声抽出 → 文字起こし
- Google Cloud Text-to-Speech連携

---

## 技術アーキテクチャ

```
┌─────────────────────────────────────┐
│       Flutter UI Layer              │
│    (Pages 26個 + Widgets 24個)      │
└──────────────────┬──────────────────┘
                   │
┌──────────────────┴──────────────────┐
│        Firebase Services            │
│  • Auth (Google/Apple Sign-In)      │
│  • Firestore (NoSQL Database)       │
│  • Storage (ファイル保存)            │
│  • Cloud Functions (22個)           │
│  • Cloud Messaging (FCM通知)        │
└──────────────────┬──────────────────┘
                   │
┌──────────────────┴──────────────────┐
│     Cloud Functions (TypeScript)    │
│  • ドキュメント処理                   │
│  • AI連携 (Gemini 2.5 Flash)        │
│  • タスク生成                        │
│  • 通知管理                          │
└──────────────────┬──────────────────┘
                   │
┌──────────────────┴──────────────────┐
│       External Services             │
│  • Vertex AI (Gemini 2.5)           │
│  • Google Cloud Text-to-Speech      │
│  • RevenueCat (課金管理)            │
│  • Google Mobile Ads (広告)         │
└─────────────────────────────────────┘
```

---

## ディレクトリ構造

```
lingosavor/
├── lib/                          # Dartソースコード
│   ├── main.dart                 # アプリエントリーポイント
│   ├── firebase_options.dart     # Firebase設定
│   ├── pages/                    # 画面コンポーネント (26ファイル)
│   │   ├── home_page.dart        # ホーム画面
│   │   ├── documents_page.dart   # ドキュメント管理
│   │   ├── savor_result_page.dart# SAVOR結果表示
│   │   ├── conversation_page.dart# AIチャット
│   │   ├── dictionary_page.dart  # 辞書
│   │   ├── subscription_page.dart# 課金管理
│   │   └── ...
│   ├── widgets/                  # UIコンポーネント (24ファイル)
│   │   ├── main_navigation.dart
│   │   ├── paywall_widget.dart
│   │   ├── savor_result_tabs/    # SAVOR結果タブ群
│   │   └── ...
│   ├── models/                   # データモデル
│   └── services/                 # サービス層
│       ├── admob_service.dart    # 広告管理
│       └── notification_service.dart
├── functions/                    # Firebase Cloud Functions
│   └── src/                      # TypeScript関数 (22ファイル)
│       ├── savor-document.ts     # SAVOR処理
│       ├── generate-meanings.ts  # 意味生成
│       ├── transcribe-*.ts       # 各種文字起こし
│       └── ...
├── android/                      # Androidネイティブ
├── ios/                          # iOSネイティブ
├── web/                          # Webビルド
├── pubspec.yaml                  # Flutter依存関係
├── firebase.json                 # Firebase設定
├── firestore.rules               # Firestoreセキュリティ
└── storage.rules                 # Storageセキュリティ
```

---

## 主要依存パッケージ

### Flutter (pubspec.yaml)

| カテゴリ | パッケージ |
|---------|-----------|
| Firebase | firebase_core, firebase_auth, cloud_firestore, firebase_storage, cloud_functions, firebase_messaging |
| 認証 | google_sign_in, sign_in_with_apple |
| ファイル処理 | file_picker, image_picker, flutter_doc_scanner, pdf_render |
| メディア | flutter_tts, audioplayers |
| 課金 | purchases_flutter (RevenueCat), in_app_purchase |
| 広告 | google_mobile_ads |
| UI | showcaseview, flutter_markdown |

### Cloud Functions (package.json)

| パッケージ | 用途 |
|-----------|------|
| firebase-admin | Firebase管理 |
| firebase-functions | Cloud Functions |
| @google-cloud/vertexai | Gemini AI連携 |
| @google-cloud/text-to-speech | 音声合成 |
| fluent-ffmpeg | 動画音声抽出 |
| pdf-lib | PDF処理 |

---

## データベース設計 (Firestore)

```
users/                    # ユーザー情報
  {userId}/
    - plan: string        # free/premium
    - remove_ads: boolean
    - gems: number

user_documents/           # アップロードドキュメント
  - user_id, title, type, path, status, transcription

user_rooms/               # 会話ルーム
messages/                 # チャットメッセージ
user_wordlists/           # 単語リスト
user_words/               # 保存単語
user_words_sparked/       # 重要マーク単語
dictionary/               # 辞書データ
user_tasks/               # 日次タスク
subscriptions/            # サブスクリプション情報
```

---

## Cloud Functions一覧

### ドキュメント処理
- `transcribeDocument` - PDF文字起こし
- `transcribeAudio` - 音声文字起こし
- `transcribeImages` - 画像OCR
- `transcribeVideo` - 動画文字起こし
- `savorDocument` - SAVOR解析処理

### AI生成
- `generateMeanings` - 単語意味生成
- `generateResponse` - AIチャット応答
- `textToSpeech` - 音声合成

### ユーザー管理
- `createUserdata` - ユーザー初期化
- `deleteAccount` - アカウント削除
- `updateUserPlans` - プラン更新

### タスク・通知
- `createDailyTasks` - 日次タスク生成
- `sendPushNotification` - プッシュ通知
- `sendDailyNotification` - 定期通知
- `saveFCMToken` - FCMトークン保存

### 課金・クリーンアップ
- `syncRevenueCatSubscription` - RevenueCat同期
- `addGems` / `addMonthlyFreeGems` - Gems管理
- `deleteUnusedWordlists` - 未使用データ削除

---

## ビジネスモデル

### Freemiumモデル

| プラン | 特徴 |
|-------|------|
| 無料版 | 基本機能 + 広告表示 |
| プレミアム | 全機能解放 + 広告非表示 |

### マネタイズ
- **サブスクリプション**: RevenueCat経由
- **アプリ内課金**: Gems（アプリ内通貨）
- **広告収入**: Google Mobile Ads

---

## 対象ユーザー

- 英語学習者（初心者〜中級者）
- PDFやドキュメントを活用した学習を希望する人
- AIによる個別フィードバックを求める人
- マルチプラットフォームでシームレスに学習したい人

---

## 開発情報

- **Flutter SDK**: 3.8.1以上
- **Node.js**: 22（Cloud Functions）
- **AI Model**: Gemini 2.5 Flash / Gemini 2.5 Flash Lite

---

## ライセンス・プライバシー

- 利用規約: `terms_of_service_page.dart`
- プライバシーポリシー: `privacy_policy_page.dart`
