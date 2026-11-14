import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../components/content_width.dart';
import '../../../components/district_picker.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/models/event_model.dart';
import '../../events/repositories/event_repository.dart';
import '../../events/widgets/event_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  SportType? _sport;
  String? _city;
  String? _area;
  DateTime? _day;
  int _refresh = 0;

  String? get _district =>
      _city != null && _area != null ? '$_city$_area' : null;

  bool get _hasActiveFilters => _sport != null || _city != null || _day != null;

  void _clearFilters() {
    setState(() {
      _sport = null;
      _city = null;
      _area = null;
      _day = null;
    });
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _logout(AuthRepository auth) async {
    await auth.logout();
    if (mounted && auth.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final repository = context.read<EventRepository>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.sports_basketball, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('揪咖 Jiuka'),
          ],
        ),
        actions: [
          if (auth.isAuthenticated) ...[
            IconButton(
              tooltip: '我的場次',
              onPressed: () => context.push('/my-events'),
              icon: const Icon(Icons.event_note_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '帳號',
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (value) => switch (value) {
                'logout' => _logout(auth),
                _ => context.push(value),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(auth.currentUser?.name ?? ''),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: '/profile', child: Text('個人檔案')),
                const PopupMenuItem(value: '/groups', child: Text('我的球隊')),
                const PopupMenuItem(value: 'logout', child: Text('登出')),
              ],
            ),
            const SizedBox(width: 8),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => context.push('/login?from=/'),
                child: const Text('Google 登入'),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<Event>>(
        key: ValueKey((_sport, _city, _area, _day, _refresh)),
        stream: repository.searchUpcomingEvents(
          sport: _sport,
          city: _city,
          district: _district,
          day: _day,
        ),
        builder: (context, snapshot) {
          final events = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '找打球場次',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '籃球、羽球缺人就上揪咖，一起分攤場租',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _filters(context),
                    const SizedBox(height: 20),
                    if (snapshot.hasError)
                      _StatusMessage(
                        icon: Icons.cloud_off_outlined,
                        message: '載入場次失敗，請檢查連線或稍後重試。',
                        action: OutlinedButton.icon(
                          onPressed: () => setState(() => _refresh++),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新載入'),
                        ),
                      )
                    else if (events == null)
                      const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (events.isEmpty)
                      _StatusMessage(
                        icon: Icons.event_busy_outlined,
                        message: _hasActiveFilters
                            ? '找不到符合條件的場次'
                            : '目前沒有開放報名的場次',
                        action: _hasActiveFilters
                            ? OutlinedButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(Icons.filter_alt_off),
                                label: const Text('清除篩選條件'),
                              )
                            : null,
                      )
                    else ...[
                      Text(
                        '共 ${events.length} 場',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final event in events) ...[
                        EventCard(
                          event: event,
                          onTap: () => context.push('/event/${event.id}'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => auth.isAuthenticated
            ? context.push('/create-event')
            : context.push('/login?from=/create-event'),
        icon: const Icon(Icons.add),
        label: const Text('發布缺人場次'),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (sport, label) in [
                  (null, '全部'),
                  (SportType.basketball, '籃球'),
                  (SportType.badminton, '羽毛球'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    avatar: sport == null ? null : Icon(sport.icon, size: 18),
                    selected: _sport == sport,
                    onSelected: (_) => setState(() => _sport = sport),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DistrictPicker(
              city: _city,
              area: _area,
              allowAny: true,
              onChanged: (city, area) => setState(() {
                _city = city;
                _area = area;
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      _day == null
                          ? '任何日期'
                          : '${DateFormat('yyyy/MM/dd').format(_day!)} ${weekdayLabel(_day!)}',
                    ),
                  ),
                ),
                if (_day != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '清除日期',
                    onPressed: () => setState(() => _day = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
                if (_hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('清除篩選'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const _StatusMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
