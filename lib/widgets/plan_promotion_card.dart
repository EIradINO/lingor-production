import 'package:flutter/material.dart';
import '../pages/subscription_page.dart';

class PlanPromotionCard extends StatelessWidget {
  final String userPlan;

  const PlanPromotionCard({
    super.key,
    required this.userPlan,
  });

  @override
  Widget build(BuildContext context) {
    if (userPlan == 'pro') {
      // pro の場合は何も表示しない
      return const SizedBox.shrink();
    } else if (userPlan == 'free' || userPlan == 'adfree') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue[700]!,
              Colors.blue[400]!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LingoSavor Pro',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              // '🚫 広告のない快適な学習\n🧠 さらに賢いAIモデル\n💎 最もコスパの良いGEM購入',
              '🧠 さらに賢いAIモデル\n💎 最もコスパの良いGEM購入',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SubscriptionPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue[600],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'プランをアップグレード',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // pro またはその他の場合は何も表示しない
      return const SizedBox.shrink();
    }
  }
}
