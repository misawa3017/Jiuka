import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';

class CreateEventScreen extends StatefulWidget {
  final String groupId;
  const CreateEventScreen({super.key, this.groupId = ''});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _districtController = TextEditingController();
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

  @override
  void dispose() {
    for (final controller in [
      _districtController,
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
    if (!start.isAfter(DateTime.now()) ||
        !end.isAfter(start) ||
        existingPlayers > maxPlayers) {
      setState(() => _error = '請確認時間仍在未來，且已有人數沒有超過總名額。');
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      await context.read<EventRepository>().createEvent(
        Event(
          id: const Uuid().v4(),
          groupId: widget.groupId,
          organizerId: organizer.id,
          sport: _sport,
          district: _districtController.text.trim(),
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
    } catch (_) {
      if (mounted) setState(() => _error = '發布失敗，請確認連線後重試。');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = int.tryParse(_friendsController.text) ?? 0;
    final players = friends + (_organizerPlaying ? 1 : 0);
    final maxPlayers = int.tryParse(_maxPlayersController.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('發布缺人場次')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            TextFormField(
              controller: _districtController,
              decoration: const InputDecoration(
                labelText: '地區',
                hintText: '例如：台北市大安區',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '請輸入地區' : null,
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
              '已有人數：$players　尚缺：${(maxPlayers - players).clamp(0, maxPlayers)}',
            ),
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
              child: Text(_isCreating ? '發布中…' : '發布場次'),
            ),
          ],
        ),
      ),
    );
  }
}
