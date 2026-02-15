import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/terms_of_service_page.dart';
import '../pages/privacy_policy_page.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  Offerings? _offerings;
  bool _isProcessingPurchase = false;
  
  // User data
  String _currentPlan = 'free';
  List<dynamic> _purchaseData = [];
  bool _isLoadingUserData = true;
  
  // Selected plan types for UI state
  String _selectedProType = 'annual'; // 'monthly' or 'annual'
  String _selectedAdFreeType = 'annual'; // 'monthly' or 'annual'

  @override
  void initState() {
    super.initState();
    _initializeRevenueCat();
    _loadUserData();
  }

  /// RevenueCatの初期化とOfferingsの取得
  Future<void> _initializeRevenueCat() async {
    try {
      // Offeringsを取得
      final offerings = await Purchases.getOfferings();
      
      setState(() {
        _offerings = offerings;
      });
      
    } catch (e) {
      if (mounted) {
        _showErrorDialog('プラン情報の取得に失敗しました。しばらく待ってから再度お試しください。');
      }
    }
  }

  /// ユーザーデータの読み込み
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoadingUserData = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _currentPlan = data['plan'] ?? 'free';
          _purchaseData = data['purchase_data'] ?? [];
          _isLoadingUserData = false;
        });
      } else {
        setState(() {
          _isLoadingUserData = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingUserData = false;
      });
    }
  }

  /// 現在の製品IDを取得
  String? _getCurrentProductId() {
    if (_purchaseData.isEmpty) return null;
    return _purchaseData.last as String?;
  }

  /// プランの表示名を取得
  String _getPlanDisplayName(String plan) {
    switch (plan.toLowerCase()) {
      case 'free':
        return 'Freeプラン';
      case 'adfree':
        return 'AdFreeプラン';
      case 'pro':
        return 'Proプラン';
      default:
        return 'Freeプラン';
    }
  }

  /// プランの色を取得
  Color _getPlanColor(String plan) {
    switch (plan.toLowerCase()) {
      case 'free':
        return Colors.grey;
      case 'adfree':
        return Colors.green;
      case 'pro':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// 年額節約メッセージを取得
  String? _getSavingsMessage() {
    final currentProductId = _getCurrentProductId();
    if (currentProductId == null) return null;

    if (currentProductId.contains('adfree') && !currentProductId.contains('annual')) {
      return '年額プランに変更すれば節約できます';
    } else if (currentProductId.contains('pro') && !currentProductId.contains('annual')) {
      return '年額プランに変更すれば7960円/年節約できます';
    }
    
    return null;
  }

  /// BottomButtonに表示するパッケージを取得
  Package? _getBottomButtonPackage() {
    if (_offerings?.current?.availablePackages == null) return null;
    
    final packages = _offerings!.current!.availablePackages;
    final currentProductId = _getCurrentProductId();

    // Freeプランの場合は確実にPro年額プランを推奨
    if (_currentPlan == 'free' || currentProductId == null) {
      return packages.where((p) => p.storeProduct.identifier == 'com.eisukeinoue.lingosavor.pro.annual').firstOrNull;
    }

    if (currentProductId.contains('pro.annual')) {
      // Pro年額 → 何も表示しない（最高プラン）
      return null;
    } else if (currentProductId.contains('pro')) {
      // Pro月額 → Pro年額に変更
      return packages.where((p) => p.storeProduct.identifier == 'com.eisukeinoue.lingosavor.pro.annual').firstOrNull;
    } else if (currentProductId.contains('adfree.annual')) {
      // AdFree年額 → Proプランにアップグレード
      return packages.where((p) => p.storeProduct.identifier == 'com.eisukeinoue.lingosavor.pro.annual').firstOrNull;
    } else if (currentProductId.contains('adfree')) {
      // AdFree月額 → AdFree年額に変更
      return packages.where((p) => p.storeProduct.identifier == 'com.lingosavor.adfree.annual').firstOrNull;
    }
    
    // フォールバック: Pro年額プランを推奨
    return packages.where((p) => p.storeProduct.identifier == 'com.eisukeinoue.lingosavor.pro.annual').firstOrNull;
  }



  /// RevenueCatで購入処理を実行
  Future<void> _purchasePackage(Package package) async {
    if (_isProcessingPurchase) return;
    
    try {
      setState(() {
        _isProcessingPurchase = true;
      });
      
      // 購入前にFirebaseユーザーIDでRevenueCatにログインしているか確認
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await Purchases.logIn(user.uid);
      }
      
      // RevenueCatで購入処理を実行
      await Purchases.purchasePackage(package);
      
      // 少し待ってから最新のCustomerInfoを取得
      await Future.delayed(const Duration(milliseconds: 500));
      final latestCustomerInfo = await Purchases.getCustomerInfo();
      
      // 購入後の権限を確認
      await _handlePurchaseSuccess(latestCustomerInfo);
      
    } on PlatformException catch (e) {
      _handlePurchaseError(e);
    } catch (e) {
      _showErrorDialog('購入処理中にエラーが発生しました。');
    } finally {
      setState(() {
        _isProcessingPurchase = false;
      });
    }
  }

  /// 購入成功後の処理
  Future<void> _handlePurchaseSuccess(CustomerInfo customerInfo) async {
    // アクティブな権限を確認
    final activeEntitlements = customerInfo.entitlements.active;
    
    String activePlan = 'free';
    
    // 複数エンタイトルメントがある場合はProを優先
    if (activeEntitlements.length > 1) {
      // Proがあるかチェック
      bool hasPro = false;
      for (final entitlement in activeEntitlements.values) {
        if (entitlement.productIdentifier.contains('pro')) {
          hasPro = true;
          break;
        }
      }
      
      if (hasPro) {
        activePlan = 'pro';
      } else {
        activePlan = 'adfree';
      }
      
    } else if (activeEntitlements.length == 1) {
      // 単一エンタイトルメントの場合
      final singleEntitlement = activeEntitlements.values.first;
      if (singleEntitlement.productIdentifier.contains('pro')) {
        activePlan = 'pro';
      } else if (singleEntitlement.productIdentifier.contains('adfree')) {
        activePlan = 'adfree';
      }
    }
    
    // ユーザーデータを再読み込み
    await _loadUserData();
    
    _showSuccessDialog(activePlan);
  }

  /// RevenueCat購入エラーを処理する
  void _handlePurchaseError(PlatformException error) {
    String errorMessage = '購入に失敗しました。';
    
    switch (error.code) {
      case '1': // User cancelled
        errorMessage = '購入がキャンセルされました。';
        break;
      case '2': // Store problem
        errorMessage = 'App Storeに接続できませんでした。';
        break;
      case '3': // Purchase not allowed
        errorMessage = '購入が許可されていません。設定を確認してください。';
        break;
      case '4': // Purchase invalid
        errorMessage = '無効な購入です。';
        break;
      case '5': // Product not available
        errorMessage = 'この商品は現在利用できません。';
        break;
      case '6': // Purchase already owned
        errorMessage = 'この商品は既に購入済みです。';
        break;
      case '8': // Network error
        errorMessage = 'ネットワークエラーが発生しました。';
        break;
      default:
        errorMessage = '購入処理中にエラーが発生しました。(${error.code})';
    }
    
    // ユーザーがキャンセルした場合はダイアログを表示しない
    if (error.code != '1') {
      _showErrorDialog(errorMessage);
    }
  }

  /// 成功ダイアログを表示
  void _showSuccessDialog(String plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('購入完了'),
        content: Text('ご購入ありがとうございます！${plan.toUpperCase()}プランがアクティベートされました。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // ダイアログを閉じる
              Navigator.of(context).pop(); // SubscriptionPageを閉じる
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// エラーダイアログを表示
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // RevenueCatは自動的にリソースを管理するため、特別な dispose処理は不要
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('プランをアップグレード'),
            elevation: 0,
          ),
          body: Column(
            children: [
              // 現在のプラン表示
              _buildCurrentPlanHeader(),
              
              // スクロール可能なコンテンツ
              Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                      // 比較表
                      _buildComparisonTable(),
                      const SizedBox(height: 32),
                      
                      // プラン選択セクション
                      _buildPlanSelectionSection(),
                      const SizedBox(height: 24),
                      
                      // 法的リンク
                      _buildLegalLinks(),
                      const SizedBox(height: 100), // BottomButtonのスペース
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // BottomButton
          bottomNavigationBar: _buildBottomButton(),
        ),
        
        // 赤い吹き出し
        _buildDiscountBalloon(),
      ],
    );
  }

  /// 現在のプランヘッダー
  Widget _buildCurrentPlanHeader() {
    // Firestoreの_currentPlanを優先して使用
    final actualCurrentPlan = _currentPlan;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getPlanColor(actualCurrentPlan).withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: _getPlanColor(actualCurrentPlan).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            '現在のプラン',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getPlanDisplayName(actualCurrentPlan),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: _getPlanColor(actualCurrentPlan),
            ),
          ),
        ],
      ),
    );
  }


  /// 比較表
  Widget _buildComparisonTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'プラン比較',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 4,
          child: Container(
            width: double.infinity,
            child: Table(
              border: TableBorder.all(color: Colors.grey[300]!),
              children: [
                // ヘッダー行
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[100]),
                  children: [
                    _buildTableCell('', isHeader: true),
                    _buildTableCell('Free', isHeader: true, color: Colors.grey),
                    _buildTableCell('AdFree', isHeader: true, color: Colors.green),
                    _buildTableCell('Pro', isHeader: true, color: Colors.blue),
                  ],
                ),
                // 広告行
                TableRow(
                  children: [
                    _buildTableCell('広告', isHeader: true),
                    _buildTableCell('あり'),
                    _buildTableCell('なし'),
                    _buildTableCell('なし'),
                  ],
                ),
                // AIモデル行
                TableRow(
                  children: [
                    _buildTableCell('AIモデル', isHeader: true),
                    _buildTableCell('Fast'),
                    _buildTableCell('Fast'),
                    _buildTableCell('Smart'),
                  ],
                ),
                // Gem行
                TableRow(
                  children: [
                    _buildTableCell('Gem/月', isHeader: true),
                    _buildTableCell('100個'),
                    _buildTableCell('2000個'),
                    _buildTableCell('3000個'),
                  ],
                ),
                
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// テーブルセルウィジェット
  Widget _buildTableCell(String text, {bool isHeader = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isHeader ? Colors.black87 : Colors.black54),
          fontSize: isHeader ? 14 : 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// プラン選択セクション
  Widget _buildPlanSelectionSection() {
    if (_offerings == null || _offerings!.current == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final availablePackages = _offerings!.current!.availablePackages;
    
    if (availablePackages.isEmpty) {
      return const Center(
        child: Text('現在、購入できるプランはありません。'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'プランを選択',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        // AdFreeプラン
        _buildPlanSection('AdFree', Colors.green, availablePackages),
        const SizedBox(height: 24),
        
        // Proプラン
        _buildPlanSection('Pro', Colors.blue, availablePackages),
      ],
    );
  }

  /// プランセクション
  Widget _buildPlanSection(String planType, Color color, List<Package> packages) {
    final monthlyId = 'com.eisukeinoue.lingosavor.${planType.toLowerCase()}';
    final annualId = 'com.eisukeinoue.lingosavor.${planType.toLowerCase()}.annual';
    
    final monthlyPackage = packages.where((p) => p.storeProduct.identifier == monthlyId).firstOrNull;
    final annualPackage = packages.where((p) => p.storeProduct.identifier == annualId).firstOrNull;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${planType}プラン',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
        Row(
          children: [
              Expanded(
                child: _buildPlanButton(
                  package: monthlyPackage,
                  planName: '月額プラン',
                  isAnnual: false,
                  color: color,
                  isSelected: (planType == 'Pro' && _selectedProType == 'monthly') ||
                             (planType == 'AdFree' && _selectedAdFreeType == 'monthly'),
                  onTap: () {
                    setState(() {
                      if (planType == 'Pro') {
                        _selectedProType = 'monthly';
                      } else {
                        _selectedAdFreeType = 'monthly';
                      }
                    });
                  },
                ),
              ),
            const SizedBox(width: 12),
              Expanded(
                child: _buildPlanButton(
                  package: annualPackage,
                  planName: '年額プラン',
                  isAnnual: true,
                  color: color,
                  isSelected: (planType == 'Pro' && _selectedProType == 'annual') ||
                             (planType == 'AdFree' && _selectedAdFreeType == 'annual'),
                  onTap: () {
                    setState(() {
                      if (planType == 'Pro') {
                        _selectedProType = 'annual';
                      } else {
                        _selectedAdFreeType = 'annual';
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          if (planType == 'Pro') ...[
            const SizedBox(height: 8),
            Text(
              'Proでは年額プランで7960円お得',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          // 購入ボタン
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_isProcessingPurchase) return;
                
                final selectedPackage = (planType == 'Pro' && _selectedProType == 'annual') ||
                                       (planType == 'AdFree' && _selectedAdFreeType == 'annual')
                    ? annualPackage
                    : monthlyPackage;
                
                if (selectedPackage != null) {
                  _purchasePackage(selectedPackage);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: _isProcessingPurchase
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('処理中...'),
                    ],
                  )
                : Text(_getPlanSectionButtonText(planType, monthlyPackage, annualPackage)),
            ),
          ),
        ],
      ),
    );
  }

    /// プランボタン
  Widget _buildPlanButton({
    required Package? package,
    required String planName,
    required bool isAnnual,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    if (package == null) {
      return Container(
        height: 120,
        child: Card(
          child: Center(
            child: Text(
              '商品情報が見つかりません',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 120,
      child: Card(
        elevation: isSelected ? 6 : 2,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.1),
                  color.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  planName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  package.storeProduct.priceString,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.check_circle,
                      color: color,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// BottomButtonの色を取得
  Color _getBottomButtonColor() {
    final currentProductId = _getCurrentProductId();
    
    // Freeプラン（または製品ID未設定）の場合は、推奨先がPro年額なので青
    if (_currentPlan == 'free' || currentProductId == null) {
      return Colors.blue;
    }
    
    // Pro年額の場合は青色
    if (currentProductId.contains('pro.annual')) {
      return Colors.blue;
    }
    
    // AdFree年額の場合は緑色
    if (currentProductId.contains('adfree.annual')) {
      return Colors.green;
    }
    
    // その他の場合は現在のプランの色
    return _getPlanColor(_currentPlan);
  }

  /// BottomButton
  Widget? _buildBottomButton() {
    final bottomPackage = _getBottomButtonPackage();
    final savingsMessage = _getSavingsMessage();
    
    if (bottomPackage == null && savingsMessage == null) {
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (savingsMessage != null) ...[
            Text(
              savingsMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          if (bottomPackage != null)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessingPurchase 
                  ? null 
                  : () => _purchasePackage(bottomPackage),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getBottomButtonColor(),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  elevation: 4,
                ),
                child: _isProcessingPurchase 
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('処理中...'),
                      ],
                    )
                  : Text(_getBottomButtonText(bottomPackage)),
              ),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isProcessingPurchase ? null : _restorePurchases,
            child: const Text('購入を復元'),
          ),
        ],
      ),
    );
  }

  /// BottomButtonのテキストを取得
  String _getBottomButtonText(Package package) {
    final currentProductId = _getCurrentProductId();
    final price = package.storeProduct.priceString;
    
    if (package.storeProduct.identifier.contains('pro.annual')) {
      if (currentProductId != null && currentProductId.contains('pro') && !currentProductId.contains('annual')) {
        return 'Pro年額プランに変更 $price';
      } else {
        return 'Pro年額プランを購入 $price';
      }
    } else if (package.storeProduct.identifier.contains('adfree.annual')) {
      if (currentProductId != null && currentProductId.contains('adfree') && !currentProductId.contains('annual')) {
        return 'AdFree年額プランに変更 $price';
      } else {
        return 'AdFree年額プランを購入 $price';
      }
    } else if (package.storeProduct.identifier.contains('adfree')) {
      return 'AdFree月額プランを購入 $price';
    }
    return 'プランを購入 $price';
  }

  /// プランセクションの購入ボタンテキストを取得
  String _getPlanSectionButtonText(String planType, Package? monthlyPackage, Package? annualPackage) {
    final isAnnualSelected = (planType == 'Pro' && _selectedProType == 'annual') ||
                            (planType == 'AdFree' && _selectedAdFreeType == 'annual');
    
    final selectedPackage = isAnnualSelected ? annualPackage : monthlyPackage;
    
    if (selectedPackage == null) return '購入';
    
    final price = selectedPackage.storeProduct.priceString;
    final planPeriod = isAnnualSelected ? '年額' : '月額';
    
    return '${planType}${planPeriod}プランを購入 $price';
  }

  Widget _buildLegalLinks() {
    return Row(
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
          child: const Text('利用規約'),
        ),
        const Text(' | '),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PrivacyPolicyPage(),
              ),
            );
          },
          child: const Text('プライバシーポリシー'),
        ),
      ],
    );
  }

  /// 赤い吹き出しウィジェット
  Widget _buildDiscountBalloon() {
    final bottomPackage = _getBottomButtonPackage();
    
    // 年額プラン（Pro年額またはPremium年額）の時のみ表示
    if (bottomPackage == null || 
        !bottomPackage.storeProduct.identifier.contains('annual')) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 140, // bottomNavigationBarの上に配置
      right: 20,
      child: CustomPaint(
        painter: BalloonPainter(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '月額と比べて約45%お得！',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// RevenueCatで購入復元を実行
  Future<void> _restorePurchases() async {
    if (_isProcessingPurchase) return;
    
    try {
      setState(() {
        _isProcessingPurchase = true;
      });
      
      // 購入復元前にFirebaseユーザーIDでRevenueCatにログインしているか確認
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await Purchases.logIn(user.uid);
      }
      
      // RevenueCatで購入復元を実行
      await Purchases.restorePurchases();
      
      // 復元後に最新のCustomerInfoを取得
      await Future.delayed(const Duration(milliseconds: 500));
      final latestCustomerInfo = await Purchases.getCustomerInfo();
      
      // 復元後の権限を確認
      final activeEntitlements = latestCustomerInfo.entitlements.active;
      
      if (activeEntitlements.isEmpty) {
        _showErrorDialog('復元できる購入が見つかりませんでした。');
      } else {
        // ユーザーデータを再読み込み
        await _loadUserData();
        await _handlePurchaseSuccess(latestCustomerInfo);
      }
      
    } catch (e) {
      _showErrorDialog('購入の復元に失敗しました。しばらく待ってから再度お試しください。');
    } finally {
      setState(() {
        _isProcessingPurchase = false;
      });
    }
  }
}

/// 吹き出し用のカスタムペインター
class BalloonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // 尻尾の描画（吹き出しの下部に小さな三角形）
    final path = Path();
    const tailWidth = 12.0;
    const tailHeight = 8.0;
    
    // 吹き出しの右下部分から下に向かって尻尾を描く
    final tailStartX = size.width - 30; // 右端から30px左
    final tailStartY = size.height;
    
    path.moveTo(tailStartX - tailWidth / 2, tailStartY);
    path.lineTo(tailStartX, tailStartY + tailHeight);
    path.lineTo(tailStartX + tailWidth / 2, tailStartY);
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

