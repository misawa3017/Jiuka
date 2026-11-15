import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/models/event_model.dart';
import '../models/group_model.dart';
import '../models/season_model.dart';
import '../models/venue_model.dart';
import '../repositories/group_repository.dart';

/// 新增或編輯季租（隊長或幹部）。季租成員、季費繳交與停打日在季租頁管理。
class SeasonFormScreen extends StatefulWidget {
  final String groupId;
  final String? seasonId;
  const SeasonFormScreen({super.key, required this.groupId, this.seasonId});

  @override
  State<SeasonFormScreen> createState() => _SeasonFormScreenState();
}

class _SeasonFormScreenState extends State<SeasonFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _capacity = TextEditingController(text: '12');
  final _rent = TextEditingController();
  final _fee = TextEditingController();
  final _dropIn = TextEditingController(text: '150');

  late final Stream<List<Venue>> _venues = context
      .read<GroupRepository>()
      .watchVenues(widget.groupId);
  Season? _original;
  bool _loaded = false;

  Venue? _venue;
  DateTime? _start;
  DateTime? _end;
  int _dayOfWeek = 3;
  TimeOfDay _startTime = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);
  bool _inviteOnly = true;
  int _openDaysBefore = 7;
  int _cancelDeadlineHours = 24;
  String? _organizerId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seasonId = widget.seasonId;
    if (seasonId == null) {
      _loaded = true;
      return;
    }
    context
        .read<GroupRepository>()
        .watchSeason(widget.groupId, seasonId)
        .first
        .then((season) {
          if (!mounted || season == null) return;
          setState(() {
            _original = season;
            _name.text = season.name;
            _capacity.text = '${season.capacity}';
            _rent.text = '${season.totalRent}';
            _fee.text = '${season.feePerMember}';
            _dropIn.text = '${season.dropInFee}';
            _start = DateTime.tryParse(season.startDate);
            _end = DateTime.tryParse(season.endDate);
            _dayOfWeek = season.dayOfWeek;
            _startTime = _parseTime(season.startTime);
            _endTime = _parseTime(season.endTime);
            _inviteOnly = season.dropInMode == 'inviteOnly';
            _openDaysBefore = season.openDaysBefore;
            _cancelDeadlineHours = season.cancelDeadlineHours;
            _organizerId = season.organizerId;
            _loaded = true;
          });
        });
  }

  @override
  void dispose() {
    for (final c in [_name, _capacity, _rent, _fee, _dropIn]) {
      c.dispose();
    }
    super.dispose();
  }

  static TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 20,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? _start ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        _dayOfWeek = picked.weekday;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() => start ? _startTime = picked : _endTime = picked);
  }

  Future<void> _save(Group group) async {
    if (!_formKey.currentState!.validate()) return;
    final venue = _venue;
    if (venue == null && _original == null) {
      setState(() => _error = '請選擇常用場地；沒有的話請先到「常用場地」新增。');
      return;
    }
    if (_start == null || _end == null || _end!.isBefore(_start!)) {
      setState(() => _error = '請確認開始與結束日期。');
      return;
    }
    if (_formatTime(_startTime).compareTo(_formatTime(_endTime)) >= 0) {
      setState(() => _error = '結束時間要晚於開始時間。');
      return;
    }
    final capacity = int.parse(_capacity.text.trim());
    final members = _original?.memberIds ?? const <String>[];
    if (members.length > capacity) {
      setState(() => _error = '目前有 ${members.length} 位季租成員，容納人數至少要這麼多。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final original = _original;
    try {
      final id = await context.read<GroupRepository>().saveSeason(
        widget.groupId,
        Season(
          id: original?.id ?? '',
          name: _name.text.trim(),
          venueId: venue?.id ?? original!.venueId,
          venueName: venue?.name ?? original!.venueName,
          city: venue?.city ?? original!.city,
          district: venue?.district ?? original!.district,
          startDate: Season.formatDate(_start!),
          endDate: Season.formatDate(_end!),
          dayOfWeek: _dayOfWeek,
          startTime: _formatTime(_startTime),
          endTime: _formatTime(_endTime),
          capacity: capacity,
          totalRent: int.parse(_rent.text.trim()),
          feePerMember: int.parse(_fee.text.trim()),
          dropInFee: int.parse(_dropIn.text.trim()),
          dropInMode: _inviteOnly ? 'inviteOnly' : 'public',
          openDaysBefore: _openDaysBefore,
          cancelDeadlineHours: _cancelDeadlineHours,
          organizerId: _organizerId ?? group.adminId,
          skipDates: original?.skipDates ?? const [],
          memberIds: members,
          paidMemberIds: original?.paidMemberIds ?? const [],
          active: original?.active ?? true,
          lastCreatedFor: original?.lastCreatedFor ?? '',
        ),
      );
      if (!mounted) return;
      if (original == null) {
        context.pushReplacement('/group/${widget.groupId}/season/$id');
      } else {
        context.pop();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '儲存失敗，請確認欄位後重試。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _number(String? value, {int min = 0}) =>
      (int.tryParse((value ?? '').trim()) ?? min - 1) >= min ? null : '請輸入數字';

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthRepository>().currentUser?.id;
    final group = context
        .watch<GroupRepository>()
        .groups
        .where((g) => g.id == widget.groupId)
        .firstOrNull;
    final editing = widget.seasonId != null;
    if (group == null || !_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!group.canManage(userId)) {
      return Scaffold(
        appBar: AppBar(title: const Text('季租')),
        body: const Center(child: Text('只有隊長或幹部可以設定季租。')),
      );
    }
    final organizers = [group.adminId, ...group.officerIds];
    final dates = DateFormat('yyyy/MM/dd');

    return Scaffold(
      appBar: AppBar(title: Text(editing ? '編輯季租' : '新增季租')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ContentWidth(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(group),
                child: Text(_saving ? '儲存中…' : '儲存季租'),
              ),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: '場地與時段',
                    icon: Icons.stadium_outlined,
                    children: [
                      TextFormField(
                        controller: _name,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: '季租名稱',
                          hintText: '例如：2027 Q1 週三夜',
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? '請輸入名稱' : null,
                      ),
                      StreamBuilder<List<Venue>>(
                        stream: _venues,
                        builder: (context, snapshot) {
                          final venues = snapshot.data ?? const <Venue>[];
                          return DropdownButtonFormField<Venue>(
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: editing && _venue == null
                                  ? '常用場地（目前：${_original?.venueName}）'
                                  : '常用場地',
                            ),
                            items: [
                              for (final venue in venues)
                                DropdownMenuItem(
                                  value: venue,
                                  child: Text(
                                    venue.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (venue) => setState(() {
                              _venue = venue;
                              if (venue != null && !editing) {
                                _capacity.text = '${venue.maxPlayers}';
                              }
                            }),
                          );
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickDate(true),
                              child: Text(
                                _start == null
                                    ? '開始日期'
                                    : '從 ${dates.format(_start!)}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickDate(false),
                              child: Text(
                                _end == null
                                    ? '結束日期'
                                    : '到 ${dates.format(_end!)}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: _dayOfWeek,
                        decoration: const InputDecoration(labelText: '每週'),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(
                              value: d,
                              child: Text('週${Season.weekdayLabels[d - 1]}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _dayOfWeek = v ?? 3),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickTime(true),
                              child: Text('開始 ${_formatTime(_startTime)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickTime(false),
                              child: Text('結束 ${_formatTime(_endTime)}'),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _capacity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '場地容納人數',
                          suffixText: '人',
                          helperText: '季租成員＋臨打的上限',
                        ),
                        validator: (v) => _number(v, min: 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '費用',
                    icon: Icons.payments_outlined,
                    children: [
                      TextFormField(
                        controller: _rent,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '整季場租',
                          suffixText: '元',
                        ),
                        validator: _number,
                        onChanged: (_) => setState(() {}),
                      ),
                      TextFormField(
                        controller: _fee,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '每人季費',
                          suffixText: '元',
                          helperText: switch (_original?.memberIds.length) {
                            final n? when n > 0 =>
                              '參考：場租 ÷ $n 人 ≈ '
                                  '${((int.tryParse(_rent.text) ?? 0) / n).ceil()} 元',
                            _ => '勾選季租成員後，季租頁會顯示「場租 ÷ 人數」參考值',
                          },
                        ),
                        validator: _number,
                      ),
                      TextFormField(
                        controller: _dropIn,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '臨打費（每人每場）',
                          suffixText: '元',
                        ),
                        validator: _number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '每週場次',
                    icon: Icons.event_repeat,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('臨打先開放給隊員與熟人'),
                        subtitle: const Text('場次先不出現在首頁；主揪再按「開放公開報名」'),
                        value: _inviteOnly,
                        onChanged: (v) => setState(() => _inviteOnly = v),
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: _openDaysBefore,
                        decoration: const InputDecoration(
                          labelText: '提前幾天開出每週場次',
                        ),
                        items: [
                          for (final d in const [1, 2, 3, 5, 7, 10, 14])
                            DropdownMenuItem(value: d, child: Text('$d 天前')),
                        ],
                        onChanged: (v) =>
                            setState(() => _openDaysBefore = v ?? 7),
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: _cancelDeadlineHours,
                        decoration: const InputDecoration(labelText: '請假與取消期限'),
                        items: [
                          for (final h in Event.cancelDeadlineOptions)
                            DropdownMenuItem(
                              value: h,
                              child: Text(h == 0 ? '不限' : '開始前 $h 小時'),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _cancelDeadlineHours = v ?? 24),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: organizers.contains(_organizerId)
                            ? _organizerId
                            : group.adminId,
                        decoration: const InputDecoration(labelText: '負責的主揪'),
                        items: [
                          for (final id in organizers)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                group.memberNames[id]?.isNotEmpty == true
                                    ? group.memberNames[id]!
                                    : '成員',
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _organizerId = v),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
