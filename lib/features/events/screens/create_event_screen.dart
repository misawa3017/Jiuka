import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../components/content_width.dart';
import '../../../components/district_picker.dart';
import '../../../core/data/taiwan_districts.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';
import '../widgets/event_card.dart';

class CreateEventScreen extends StatefulWidget {
  final String groupId;

  /// 有值時為編輯模式：表單預填此場次，送出時呼叫 updateEvent。
  final Event? initialEvent;

  const CreateEventScreen({super.key, this.groupId = '', this.initialEvent});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  // 地區由下拉選單選擇；舊場次的地區若不在清單內，編輯時需重新選擇。
  String? _city;
  String? _area;
  final _titleController = TextEditingController();
  final _venueController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _maxPlayersController = TextEditingController(text: '10');
  final _friendsController = TextEditingController(text: '0');
  SportType _sport = SportType.basketball;
  CostMode _costMode = CostMode.perPerson;
  bool _organizerPlaying = true;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);
  bool _isCreating = false;
  String? _error;

  bool get _isEditing => widget.initialEvent != null;

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent;
    if (event == null) return;
    _city = cityOfDistrict(event.district);
    _area = areaOfDistrict(event.district);
    _titleController.text = event.title;
    _venueController.text = event.venue;
    _descriptionController.text = event.description;
    _costController.text = '${event.cost}';
    _maxPlayersController.text = '${event.maxPlayers}';
    _friendsController.text =
        '${event.existingPlayers - (event.organizerPlaying ? 1 : 0)}';
    _sport = event.sport ?? SportType.basketball;
    _costMode = event.costMode;
    _organizerPlaying = event.organizerPlaying;
    _selectedDate = DateUtils.dateOnly(event.startTime);
    _startTime = TimeOfDay.fromDateTime(event.startTime);
    _endTime = TimeOfDay.fromDateTime(event.endTime);
  }

  @override
  void dispose() {
    for (final controller in [
      _titleController,
      _venueController,
      _descriptionController,
      _costController,
      _maxPlayersController,
      _friendsController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final organizer = context.read<AuthRepository>().currentUser;
    if (organizer == null) {
      context.go('/login?from=/create-event');
      return;
    }
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endToday = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );
    final end = endToday.isBefore(start)
        ? endToday.add(const Duration(days: 1))
        : endToday;
    final friends = int.parse(_friendsController.text);
    final maxPlayers = int.parse(_maxPlayersController.text);
    final existingPlayers = friends + (_organizerPlaying ? 1 : 0);
    final attendees = widget.initialEvent?.attendeeCount ?? 0;
    if (!start.isAfter(DateTime.now()) ||
        !end.isAfter(start) ||
        existingPlayers + attendees > maxPlayers) {
      setState(
        () => _error = attendees > 0
            ? '請確認時間仍在未來；目前已有 $attendees 位正取球友，總名額至少要 ${existingPlayers + attendees} 人。'
            : '請確認時間仍在未來，且已有人數沒有超過總名額。',
      );
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    final repository = context.read<EventRepository>();
    try {
      if (widget.initialEvent case final original?) {
        await repository.updateEvent(
          original.copyWith(
            title: _titleController.text.trim(),
            sport: _sport,
            city: _city!,
            district: '$_city$_area',
            venue: _venueController.text.trim(),
            description: _descriptionController.text.trim(),
            existingPlayers: existingPlayers,
            organizerPlaying: _organizerPlaying,
            startTime: start,
            endTime: end,
            costMode: _costMode,
            cost: int.parse(_costController.text),
            maxPlayers: maxPlayers,
          ),
        );
        if (mounted) context.pop();
        return;
      }
      await repository.createEvent(
        Event(
          id: const Uuid().v4(),
          groupId: widget.groupId,
          organizerId: organizer.id,
          title: _titleController.text.trim(),
          sport: _sport,
          city: _city!,
          district: '$_city$_area',
          venue: _venueController.text.trim(),
          description: _descriptionController.text.trim(),
          existingPlayers: existingPlayers,
          organizerPlaying: _organizerPlaying,
          startTime: start,
          endTime: end,
          costMode: _costMode,
          cost: int.parse(_costController.text),
          maxPlayers: maxPlayers,
        ),
      );
      if (mounted) context.pop();
    } on FirebaseFunctionsException catch (error) {
      // 後端驗證失敗（例如名額低於正取人數）時，直接顯示伺服器的說明。
      if (mounted) {
        setState(() => _error = error.message ?? '儲存失敗，請確認連線後重試。');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _isEditing ? '儲存失敗，請確認連線後重試。' : '發布失敗，請確認連線後重試。',
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final friends = int.tryParse(_friendsController.text) ?? 0;
    final players = friends + (_organizerPlaying ? 1 : 0);
    final maxPlayers = int.tryParse(_maxPlayersController.text) ?? 0;
    final original = widget.initialEvent;
    final occupied = players + (original?.attendeeCount ?? 0);
    final missing = (maxPlayers - occupied).clamp(0, maxPlayers);
    final submitLabel = _isEditing
        ? (_isCreating ? '儲存中…' : '儲存變更')
        : (_isCreating ? '發布中…' : '發布場次');

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯場次' : '發布缺人場次')),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ContentWidth(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isCreating ? null : _submit,
                child: Text(submitLabel),
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
                  if (original != null &&
                      original.attendeeCount + original.waitlistCount > 0) ...[
                    _Notice(
                      text:
                          '已有 ${original.attendeeCount + original.waitlistCount} 位球友報名。'
                          '目前沒有通知功能，修改時間、地點或費用後請自行告知他們；'
                          '場次頁會顯示「主揪更新過場次資訊」。',
                    ),
                    const SizedBox(height: 12),
                  ],
                  SectionCard(
                    title: '基本資訊',
                    icon: Icons.sports_outlined,
                    children: [
                      TextFormField(
                        controller: _titleController,
                        maxLength: Event.maxTitleLength,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '活動名稱（選填）',
                          hintText: '例如：週三晚間籃球揪團',
                          prefixIcon: Icon(Icons.title),
                          helperText: '沒填的話會以球館名稱當標題',
                        ),
                      ),
                      SegmentedButton<SportType>(
                        segments: [
                          for (final sport in SportType.values)
                            ButtonSegment(
                              value: sport,
                              icon: Icon(sport.icon),
                              label: Text(sport.label),
                            ),
                        ],
                        selected: {_sport},
                        onSelectionChanged: (value) =>
                            setState(() => _sport = value.first),
                      ),
                      DistrictPicker(
                        city: _city,
                        area: _area,
                        onChanged: (city, area) => setState(() {
                          _city = city;
                          _area = area;
                        }),
                      ),
                      TextFormField(
                        controller: _venueController,
                        decoration: const InputDecoration(
                          labelText: '球館／地點',
                          hintText: '例如：大安運動中心 3 樓',
                          prefixIcon: Icon(Icons.stadium_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '請輸入地點'
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '時間',
                    icon: Icons.schedule,
                    children: [
                      _PickerField(
                        label: '日期',
                        icon: Icons.calendar_today_outlined,
                        value:
                            '${DateFormat('yyyy/MM/dd').format(_selectedDate)} ${weekdayLabel(_selectedDate)}',
                        onTap: _pickDate,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _PickerField(
                              label: '開始',
                              icon: Icons.play_arrow_outlined,
                              value: _startTime.format(context),
                              onTap: () => _pickTime(true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PickerField(
                              label: '結束',
                              icon: Icons.stop_outlined,
                              value: _endTime.format(context),
                              onTap: () => _pickTime(false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '人數',
                    icon: Icons.group_outlined,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _maxPlayersController,
                              decoration: const InputDecoration(
                                labelText: '總名額',
                                suffixText: '人',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: (value) =>
                                  (int.tryParse(value ?? '') ?? 0) >= 2
                                  ? null
                                  : '至少 2 人',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _friendsController,
                              decoration: const InputDecoration(
                                labelText: '已約好的球友',
                                helperText: '不含主揪',
                                suffixText: '人',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: (value) =>
                                  (int.tryParse(value ?? '') ?? -1) >= 0
                                  ? null
                                  : '請輸入有效人數',
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('主揪也會上場'),
                        subtitle: const Text('開啟後主揪會占用 1 個名額'),
                        value: _organizerPlaying,
                        onChanged: (value) =>
                            setState(() => _organizerPlaying = value),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已有 $occupied 人，尚缺 $missing 人',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (original != null && original.attendeeCount > 0)
                              Text(
                                '含 App 報名的正取球友 ${original.attendeeCount} 人',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            if (original != null && original.waitlistCount > 0)
                              Text(
                                '名額增加時，候補球友會依報名順序自動遞補。',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '費用',
                    icon: Icons.payments_outlined,
                    children: [
                      SegmentedButton<CostMode>(
                        segments: const [
                          ButtonSegment(
                            value: CostMode.perPerson,
                            label: Text('每人固定'),
                          ),
                          ButtonSegment(
                            value: CostMode.totalVenue,
                            label: Text('整場場租平分'),
                          ),
                        ],
                        selected: {_costMode},
                        onSelectionChanged: (value) =>
                            setState(() => _costMode = value.first),
                      ),
                      TextFormField(
                        controller: _costController,
                        decoration: InputDecoration(
                          labelText: _costMode == CostMode.perPerson
                              ? '每人費用'
                              : '整場場租',
                          suffixText: '元',
                          helperText: _costMode == CostMode.totalVenue
                              ? '每人金額依已確定人數估算，報名時顯示預估金額'
                              : null,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            (int.tryParse(value ?? '') ?? -1) >= 0
                            ? null
                            : '請輸入有效金額',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '補充說明',
                    icon: Icons.notes,
                    children: [
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          hintText: '選填，例如：程度、球衣顏色、停車資訊',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _Notice(text: _error!, isError: true),
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

/// 點擊後開啟日期／時間選擇器的欄位，外觀與輸入框一致。
class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Text(value),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool isError;
  const _Notice({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.tertiary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
