import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'services/admob_service.dart';
import 'services/notification_service.dart';

const String _revenueCatApiKey = 'appl_gdgaILTcUODMulfQszuRurZnlFf';

// バックグラウンドメッセージハンドラー
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // バックグラウンドでの通知処理（必要に応じて実装）
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // バックグラウンドメッセージハンドラーの設定
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // その他の初期化
  await _configurePurchases();
  
  // AdMob初期化
  await AdMobService.initialize();
  
  runApp(const MyApp());
}

Future<void> _configurePurchases() async {
  await Purchases.setLogLevel(LogLevel.debug); // 開発中はデバッグログを有効に
  PurchasesConfiguration configuration;

  // iOS用の設定
  configuration = PurchasesConfiguration(_revenueCatApiKey);
  await Purchases.configure(configuration);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LingoSavorのブランドカラー
    const Color lingoSavorPrimary = Color(0xFF8ACE00);
    
    return MaterialApp(
      title: 'LingoSavor',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: lingoSavorPrimary,
          primary: lingoSavorPrimary,
          brightness: Brightness.light,
        ).copyWith(
          // カスタムカラーの定義
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        useMaterial3: true,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        // アプリバーテーマ
        appBarTheme: const AppBarTheme(
          backgroundColor: lingoSavorPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // ボタンテーマ
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: lingoSavorPrimary,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}
