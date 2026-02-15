import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../widgets/main_navigation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  
  bool _isInitialized = false;
  
  // ナビゲーション用のGlobalKey
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 通知サービスを初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // ローカル通知の初期化
      await _initializeLocalNotifications();
      
      // FCMの初期化
      await _initializeFirebaseMessaging();
      
      _isInitialized = true;
      if (kDebugMode) {
        print('NotificationService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize NotificationService: $e');
      }
    }
  }

  /// ローカル通知の初期化
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Firebase Messagingの初期化
  Future<void> _initializeFirebaseMessaging() async {
    // 通知の許可をリクエスト
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      print('User granted permission: ${settings.authorizationStatus}');
    }

    // FCMトークンの取得と保存
    await _getFCMTokenAndSave();

    // フォアグラウンド時のメッセージ処理
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // バックグラウンド/終了状態からの通知タップ処理
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // アプリが終了状態から通知で起動された場合の処理
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // トークン更新時の処理
    _messaging.onTokenRefresh.listen(_onTokenRefresh);
  }

  /// FCMトークンを取得してCloud Functionsで保存
  Future<void> _getFCMTokenAndSave() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String? token = await _messaging.getToken();
      if (token != null) {
        if (kDebugMode) {
          print('FCM Token: $token');
        }

        // Cloud Functionsを使ってFCMトークンを保存
        final callable = _functions.httpsCallable('saveFCMToken');
        final result = await callable.call({
          'token': token,
        });

        if (kDebugMode) {
          print('FCM Token saved via Cloud Functions: ${result.data}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting/saving FCM token: $e');
      }
    }
  }

  /// トークン更新時の処理
  Future<void> _onTokenRefresh(String token) async {
    if (kDebugMode) {
      print('FCM Token refreshed: $token');
    }
    await _getFCMTokenAndSave();
  }

  /// フォアグラウンド時のメッセージ処理
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');
    }

    if (message.notification != null) {
      if (kDebugMode) {
        print('Message also contained a notification: ${message.notification}');
      }

      // フォアグラウンド時はローカル通知として表示
      await _showLocalNotification(message);
    }
  }

  /// ローカル通知を表示
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'default_channel',
      'Default Channel',
      channelDescription: 'Default notification channel',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'LingoSavor',
      message.notification?.body ?? '',
      platformChannelSpecifics,
      payload: _encodePayload(message.data),
    );
  }

  /// 通知タップ時の処理
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      print('Notification tapped: ${message.data}');
    }

    // 通知タップ時の画面遷移処理をここに実装
    // 例: 特定のページに遷移
    final String? screen = message.data['screen'];
    if (screen != null) {
      // NavigatorやRouterを使った画面遷移
      _navigateToScreen(screen, message.data);
    }
  }

  /// ローカル通知タップ時の処理
  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Local notification tapped: ${response.payload}');
    }

    if (response.payload != null) {
      final Map<String, dynamic> data = _decodePayload(response.payload!);
      final String? screen = data['screen'];
      if (screen != null) {
        _navigateToScreen(screen, data);
      }
    }
  }

  /// 画面遷移処理
  void _navigateToScreen(String screen, Map<String, dynamic> data) {
    if (kDebugMode) {
      print('Navigate to screen: $screen with data: $data');
    }

    // 現在のコンテキストを取得
    final context = navigatorKey.currentContext;
    if (context == null) {
      if (kDebugMode) {
        print('Context is null, cannot navigate');
      }
      return;
    }

    // MainNavigationScreenのタブインデックスを取得
    int targetTabIndex;
    
    switch (screen) {
      case 'home':
        targetTabIndex = 0; // ホームタブ
        break;
      case 'documents':
        targetTabIndex = 1; // ドキュメントタブ
        break;
      default:
        if (kDebugMode) {
          print('Unknown screen: $screen, defaulting to home');
        }
        targetTabIndex = 0; // デフォルトはホーム
        break;
    }

    // MainNavigationScreenのコールバックを呼び出してタブを切り替え
    MainNavigationController.changeTab(targetTabIndex);
  }

  /// ペイロードをエンコード
  String _encodePayload(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  /// ペイロードをデコード
  Map<String, dynamic> _decodePayload(String payload) {
    final Map<String, dynamic> data = {};
    for (String pair in payload.split('|')) {
      final List<String> keyValue = pair.split(':');
      if (keyValue.length == 2) {
        data[keyValue[0]] = keyValue[1];
      }
    }
    return data;
  }

  /// 手動でFCMトークンを再取得・保存
  Future<void> refreshToken() async {
    await _getFCMTokenAndSave();
  }

  /// 通知チャンネルの作成（Android用）
  Future<void> createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'default_channel',
      'Default Channel',
      description: 'Default notification channel for LingoSavor',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
}

/// バックグラウンドメッセージハンドラー（トップレベル関数である必要がある）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('Handling a background message: ${message.messageId}');
    print('Message data: ${message.data}');
    print('Message notification: ${message.notification}');
  }
}
