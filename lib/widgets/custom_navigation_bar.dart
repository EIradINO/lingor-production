import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:showcaseview/showcaseview.dart';

class CustomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final GlobalKey? plusButtonKey;

  const CustomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.plusButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home, 'ホーム'),
                _buildNavItem(1, Icons.library_books_outlined, Icons.library_books, 'ドキュメント'),
                _buildPlusButton(context),
                _buildNavItem(3, Icons.question_answer_outlined, Icons.question_answer, '質問'),
                _buildNavItem(4, Icons.person_outline, Icons.person, 'プロフィール'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? filledIcon : outlineIcon,
                key: ValueKey('$index-$isSelected'),
                color: isSelected ? Colors.black : Colors.black54,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 8, // ここを10→8に変更
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.black : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlusButton(BuildContext context) {
    final button = GestureDetector(
      onTap: () => onTap(2),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
    
    // plusButtonKeyが提供されている場合はShowcaseでラップ
    if (plusButtonKey != null) {
      return Showcase(
        key: plusButtonKey!,
        title: '学んだ英文をアップロードしよう！',
        description: '紙の資料、PDF、リスニング音源、スクショ...なんでも文字起こし',
        targetPadding: const EdgeInsets.all(8),
        child: button,
      );
    }
    
    return button;
  }
} 