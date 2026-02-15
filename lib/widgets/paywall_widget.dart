import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// PaywallViewを表示するページウィジェット
class PaywallPage extends StatelessWidget {
  final Offering offering;

  const PaywallPage({
    super.key,
    required this.offering,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PaywallView(
          offering: offering,
          onRestoreCompleted: (CustomerInfo customerInfo) {
            // 復元が完了したときの処理
            print('Restore completed: ${customerInfo.entitlements.active}');
          },
          onDismiss: () {
            // Paywallを閉じる
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

