import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // PlatformException用
import 'package:purchases_flutter/purchases_flutter.dart';

class AdFreePurchaseCard extends StatefulWidget {
  const AdFreePurchaseCard({super.key});

  @override
  State<AdFreePurchaseCard> createState() => _AdFreePurchaseCardState();
}

class _AdFreePurchaseCardState extends State<AdFreePurchaseCard> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  
  Package? _package;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeStore();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initializeStore() async {
    try {
      final offerings = await Purchases.getOfferings();
      
      // current (default) offering から lifetime パッケージを取得
      // offeringの設定で "lifetime" として設定されているものを探す
      final package = offerings.current?.lifetime;

      if (package != null) {
        if (mounted) {
          setState(() {
            _package = package;
            _isAvailable = true;
            _isLoading = false;
          });
        }
      } else {
        print('AdFree lifetime package not found in current offering');
        if (mounted) {
          setState(() {
            _isAvailable = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('RevenueCat offerings loading error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleError(String message) {
    setState(() {
      _isPurchasing = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _buyProduct() async {
    if (_package == null) return;
    
    setState(() {
      _isPurchasing = true;
    });
    
    try {
      await Purchases.purchasePackage(_package!);
      
      // 少し待ってから最新のCustomerInfoを取得
      await Future.delayed(const Duration(milliseconds: 500));
      final customerInfo = await Purchases.getCustomerInfo();
      
      // remove_ads エンタイトルメントが付与されたか確認
      final isPro = customerInfo.entitlements.all['remove_ads']?.isActive ?? false;
      
      if (isPro) {
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('購入が完了しました！広告なしプランが有効になりました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _handleError('購入処理は完了しましたが、権限の確認ができませんでした。');
      }
      
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        _handleError('購入エラー: ${e.message}');
      } else {
        setState(() {
          _isPurchasing = false;
        });
      }
    } catch (e) {
      _handleError('予期せぬエラーが発生しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade400,
              Colors.deepPurple.shade600,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (!_isAvailable || _package == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.shade400,
            Colors.deepPurple.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '広告なしプラン',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '一度きりの購入で永久に広告なし',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFeature('すべての広告を削除'),
                const SizedBox(height: 8),
                _buildFeature('快適な学習体験'),
                const SizedBox(height: 8),
                _buildFeature('永久に有効'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPurchasing ? null : _buyProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isPurchasing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                      ),
                    )
                  : Text(
                      '${_package!.storeProduct.priceString}で購入',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
