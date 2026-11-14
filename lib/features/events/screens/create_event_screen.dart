import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../components/district_picker.dart';
import '../../../core/data/taiwan_districts.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';

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
    final friends = int.tryParse(_friendsController.text) ?? 0;
    final players = friends + (_organizerPlaying ? 1 : 0);
    final maxPlayers = int.tryParse(_maxPlayersController.text) ?? 0;
    final original = widget.initialEvent;
    final occupied = players + (original?.attendeeCount ?? 0);
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯場次' : '發布缺人場次')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (original != null &&
                original.attendeeCount + original.waitlistCount > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '已有 ${original.attendeeCount + original.waitlistCount} 位球友報名。'
                    '目前沒有通知功能，修改時間、地點或費用後請自行告知他們；'
                    '場次頁會顯示「主揪更新過場次資訊」。',
                  ),
                ),
              ),
            DropdownButtonFormField<SportType>(
              initialValue: _sport,
              decoration: const InputDecoration(labelText: '運動類型'),
              items: const [
                DropdownMenuItem(
                  value: SportType.basketball,
                  child: Text('籃球'),
                ),
                DropdownMenuItem(
                  value: SportType.badminton,
                  child: Text('羽毛球'),
                ),
              ],
              onChanged: (value) => setState(() => _sport = value!),
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
              decoration: const InputDecoration(labelText: '球館／地點'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '請輸入地點' : null,
            ),
            ListTile(
              title: Text(DateFormat('yyyy/MM/dd (EEE)').format(_selectedDate)),
              leading: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(_startTime.format(context)),
                    subtitle: const Text('開始'),
                    onTap: () => _pickTime(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: Text(_endTime.format(context)),
                    subtitle: const Text('結束'),
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _maxPlayersController,
              decoration: const InputDecoration(labelText: '總名額'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  (int.tryParse(value ?? '') ?? 0) >= 2 ? null : '至少 2 人',
            ),
            TextFormField(
              controller: _friendsController,
              decoration: const InputDecoration(labelText: '已約好的球友人數（不含主揪）'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  (int.tryParse(value ?? '') ?? -1) >= 0 ? null : '請輸入有效人數',
            ),
            CheckboxListTile(
              title: const Text('主揪也會上場'),
              value: _organizerPlaying,
              onChanged: (value) =>
                  setState(() => _organizerPlaying = value ?? false),
            ),
            Text(
              '已有人數：$occupied　尚缺：${(maxPlayers - occupied).clamp(0, maxPlayers)}',
            ),
            if (original != null && original.attendeeCount > 0)
              Text('含 App 報名的正取球友 ${original.attendeeCount} 人'),
            if (original != null && original.waitlistCount > 0)
              const Text('名額增加時，候補球友會依報名順序自動遞補。'),
            DropdownButtonFormField<CostMode>(
              initialValue: _costMode,
              decoration: const InputDecoration(labelText: '費用方式'),
              items: const [
                DropdownMenuItem(
                  value: CostMode.perPerson,
                  child: Text('每人固定費用'),
                ),
                DropdownMenuItem(
                  value: CostMode.totalVenue,
                  child: Text('整場場租，依人數預估'),
                ),
              ],
              onChanged: (value) => setState(() => _costMode = value!),
            ),
            TextFormField(
              controller: _costController,
              decoration: InputDecoration(
                labelText: _costMode == CostMode.perPerson
                    ? '每人費用（元）'
                    : '整場場租（元）',
              ),
              keyboardType: TextInputType.number,
              validator: (value) =>
                  (int.tryParse(value ?? '') ?? -1) >= 0 ? null : '請輸入有效金額',
            ),
            if (_costMode == CostMode.totalVenue)
              const Text('每人金額會隨已確定人數變動，報名時顯示預估金額。'),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '補充說明（選填）'),
              maxLines: 3,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isCreating ? null : _submit,
              child: Text(
                _isEditing
                    ? (_isCreating ? '儲存中…' : '儲存變更')
                    : (_isCreating ? '發布中…' : '發布場次'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
