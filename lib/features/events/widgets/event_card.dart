import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_model.dart';

extension SportDisplay on SportType? {
  String get label => switch (this) {
    SportType.basketball => '籃球',
    SportType.badminton => '羽毛球',
    null => '球類',
  };

  IconData get icon => switch (this) {
    SportType.badminton => Icons.sports_tennis,
    _ => Icons.sports_basketball,
  };
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayLabel(DateTime date) => '週${_weekdays[date.weekday - 1]}';

/// 費用的簡短說明，列表與詳情共用。
String costSummary(Event event, {bool joining = false}) {
  if (event.finalCostPerPerson case final amount?) return '每人 $amount 元（已確定）';
  if (event.costMode == CostMode.perPerson) return '每人 ${event.cost} 元';
  final estimate = event.estimatedCostPerPerson(joining: joining);
  return estimate == null ? '場租 ${event.cost} 元' : '每人約 $estimate 元';
}

/// 場次卡片：左側日期方塊，右側運動、時間、地點、名額進度與費用。
class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  /// 右上角的身分標籤，例如「主揪」「正取」「候補」。
  final String? badge;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final closed = !event.isAcceptingSignups;
    final full = event.isFull;
    final progress = event.maxPlayers == 0
        ? 0.0
        : (event.occupiedCount / event.maxPlayers).clamp(0.0, 1.0);
    final time = DateFormat('HH:mm');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: closed ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateBlock(date: event.startTime),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用 Wrap：標籤多或螢幕窄時自動換行，不會擠在一起或超出。
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Tag(
                            icon: event.sport.icon,
                            label: event.sport.label,
                            color: scheme.primary,
                          ),
                          Text(
                            '${time.format(event.startTime)}–${time.format(event.endTime)}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (closed)
                            _Tag(
                              label: event.status == EventStatus.cancelled
                                  ? '已取消'
                                  : '已截止',
                              color: scheme.error,
                            )
                          else if (badge != null)
                            _Tag(label: badge!, color: scheme.tertiary),
                          if (!closed && event.isInviteOnly)
                            _Tag(
                              icon: Icons.lock_outline,
                              label: '限熟人',
                              color: scheme.secondary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event.displayTitle,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              // 有活動名稱時，球館改顯示在地區後面。
                              event.title.isEmpty
                                  ? event.district
                                  : '${event.district} · ${event.venue}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (event.organizerName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '主揪 ${event.organizerName}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: full ? scheme.tertiary : scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // 人數可以縮短（太長顯示「…」），費用一定完整顯示。
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: full
                                        ? '已額滿${event.waitlistCount > 0 ? ' · 候補 ${event.waitlistCount}' : ''}'
                                        : '尚缺 ${event.spotsLeft} 人',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: full
                                          ? scheme.tertiary
                                          : scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '  ${event.occupiedCount}/${event.maxPlayers}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            costSummary(event, joining: !full),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  final DateTime date;
  const _DateBlock({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '${date.month}月',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          Text(
            '${date.day}',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            weekdayLabel(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Tag({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
