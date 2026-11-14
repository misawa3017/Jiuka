import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 限制內容最大寬度並置中：桌面版不會整排拉滿，手機維持滿版。
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = AppTheme.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    // heightFactor: 1 讓高度貼合內容；否則放在底部列時會撐滿整個畫面。
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 卡片內的區塊標題，例如發布表單的「基本資訊」。
class SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;

  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
