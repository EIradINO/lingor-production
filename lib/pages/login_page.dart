import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../widgets/main_navigation.dart';
import 'terms_of_service_page.dart';
import 'privacy_policy_page.dart';
import 'first_tutorial_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: []);

  User? _user;
  bool _tutorialShown = true;  // デフォルトはtrueにして、チェック後に更新

  @override
  void initState() {
    super.initState();
    _checkTutorialStatus();
    _auth.authStateChanges().listen((User? user) {
      setState(() {
        _user = user;
      });
      
      // ユーザーがログインした後に通知サービスを初期化とRevenueCatログイン
      if (user != null) {
        _initializeNotifications();
        _loginToRevenueCat(user);
      }
    });
  }

  // チュートリアルの表示状態をチェック
  Future<void> _checkTutorialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('tutorial_page_shown') ?? false;
    setState(() {
      _tutorialShown = shown;
    });
  }

  /// 通知サービスの初期化
  Future<void> _initializeNotifications() async {
    try {
      await NotificationService().initialize();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize notifications: $e');
      }
    }
  }

  /// RevenueCatにログイン
  Future<void> _loginToRevenueCat(User user) async {
    try {
      await Purchases.logIn(user.uid);
      if (kDebugMode) {
        print('RevenueCat logged in with user ID: ${user.uid}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to login to RevenueCat: $e');
      }
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      setState(() {
        _user = user;
      });
      if (user != null) {
        await Purchases.logIn(user.uid);
      }
      // 常にcreate-userdata関数を呼び出し、サーバー側で新規ユーザー判定
      await createUserDataIfNew();
      
      return user;

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ログインに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<User?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(oauthCredential);
      final User? user = userCredential.user;

      setState(() {
        _user = user;
      });
      if (user != null) {
        await Purchases.logIn(user.uid);
      }
      // 常にcreate-userdata関数を呼び出し、サーバー側で新規ユーザー判定
      await createUserDataIfNew();
      
      return user;

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Appleログインに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> createUserDataIfNew() async {
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createUserdata');
      final result = await callable.call();
      
      if (result.data['success'] == true) {
        print('User data created successfully');
        print('User data: ${result.data['userData']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ユーザーデータを作成しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('Skipped: ${result.data['message']}');
      }
    } catch (e) {
      print('Error calling createUserdata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ユーザーデータの作成に失敗しました: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> signOut() async {
    await Purchases.logOut();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // ログアウト状態かつチュートリアル未表示の場合はチュートリアルページを表示
    if (_user == null && !_tutorialShown) {
      return const FirstTutorialPage();
    }
    
    return Scaffold(
      body: _user == null
          ? _buildLoginScreen()
          : MainNavigationScreen(user: _user!, onSignOut: signOut),
    );
  }

  Widget _buildLoginScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // アプリアイコン
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'images/icon.png',
                  width: 120,
                  height: 120,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'LingoSavor',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '英語学習の手間を半減し\n効果を倍増させる',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 64),
            // Apple Sign In ボタン
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton(
                onPressed: signInWithApple,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 16),
                    Icon(Icons.apple, size: 28, color: Colors.white),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Appleで続ける',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: 44),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Google Sign In ボタン
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton(
                onPressed: signInWithGoogle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Image.network(
                      'https://developers.google.com/identity/images/g-logo.png',
                      height: 28,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.g_mobiledata, size: 28);
                      },
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Googleで続ける',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // 利用規約とプライバシーポリシーのリンク
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const TermsOfServicePage(),
                      ),
                    );
                  },
                  child: const Text(
                    '利用規約',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(
                  '・',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PrivacyPolicyPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'プライバシーポリシー',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ログインすることで、利用規約とプライバシーポリシーに同意したことになります。',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}