import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/models/event_model.dart';
import '../../events/repositories/event_repository.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _districtController = TextEditingController();
  SportType? _sport;
  String? _district;
  DateTime? _day;
  int _refresh = 0;

  @override
  void dispose() {
    _districtController.dispose();
    super.dispose();
  }

  void _applyDistrict() =>
      setState(() {
        final district = _districtController.text.trim();
        _district = district.isEmpty ? null : district;
      });

  bool get _hasActiveFilters =>
      _sport != null || _district != null || _day != null;

  void _clearFilters() {
    _districtController.clear();
    setState(() {
      _sport = null;
      _district = null;
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final repository = context.read<EventRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('找打球場次'),
        actions: [
          if (auth.isAuthenticated) ...[
            IconButton(
              tooltip: '我的場次',
              onPressed: () => context.push('/my-events'),
              icon: const Icon(Icons.event_note),
            ),
            IconButton(
              tooltip: '我的球隊',
              onPressed: () => context.push('/groups'),
              icon: const Icon(Icons.groups),
            ),
            IconButton(
              tooltip: '個人檔案',
              onPressed: () => context.push('/profile'),
              icon: const Icon(Icons.account_circle),
            ),
            IconButton(
              tooltip: '登出',
              onPressed: () async {
                await auth.logout();
                if (context.mounted && auth.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(auth.errorMessage!)),
                  );
                }
              },
              icon: const Icon(Icons.logout),
            ),
          ] else
            TextButton(
              onPressed: () => context.push('/login?from=/'),
              child: const Text('Google 登入'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<SportType?>(
                    initialValue: _sport,
                    decoration: const InputDecoration(labelText: '運動'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部')),
                      DropdownMenuItem(
                        value: SportType.basketball,
                        child: Text('籃球'),
                      ),
                      DropdownMenuItem(
                        value: SportType.badminton,
                        child: Text('羽毛球'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _sport = value),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _districtController,
                    decoration: InputDecoration(
                      labelText: '地區（完全相同）',
                      suffixIcon: IconButton(
                        tooltip: '搜尋地區',
                        onPressed: _applyDistrict,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) => _applyDistrict(),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _day == null
                        ? '任何日期'
                        : DateFormat('yyyy/MM/dd').format(_day!),
                  ),
                ),
                if (_day != null)
                  TextButton(
                    onPressed: () => setState(() => _day = null),
                    child: const Text('清除日期'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Event>>(
              key: ValueKey((_sport, _district, _day, _refresh)),
              stream: repository.searchUpcomingEvents(
                sport: _sport,
                district: _district,
                day: _day,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('載入場次失敗，請檢查連線或稍後重試。'),
                        TextButton(
                          onPressed: () => setState(() => _refresh++),
                          child: const Text('重試'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snapshot.data!;
                if (events.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _hasActiveFilters
                              ? '找不到符合條件的場次。'
                              : '目前沒有開放報名的場次。',
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off),
                            label: const Text('清除篩選條件'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final sportName = switch (event.sport) {
                      SportType.basketball => '籃球',
                      SportType.badminton => '羽毛球',
                      null => '球類',
                    };
                    final amount = event.estimatedCostPerPerson(
                      joining: !event.isFull,
                    );
                    final cost = event.costMode == CostMode.perPerson
                        ? '每人固定 ${event.cost} 元'
                        : amount == null
                        ? '整場 ${event.cost} 元，待估算'
                        : '整場 ${event.cost} 元，報名後每人預估 $amount 元';
                    return Card(
                      child: ListTile(
                        title: Text(
                          '$sportName · ${DateFormat('MM/dd HH:mm').format(event.startTime)}',
                        ),
                        subtitle: Text(
                          '${event.district} · ${event.venue}\n'
                          '尚缺 ${event.spotsLeft} 人 · $cost',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/event/${event.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
}
