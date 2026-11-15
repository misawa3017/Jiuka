import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../../components/district_picker.dart';
import '../../../core/data/taiwan_districts.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/models/event_model.dart';
import '../models/venue_model.dart';
import '../repositories/group_repository.dart';

/// 球隊常用場地：隊員可查看；隊長與幹部可新增、修改、刪除。
class VenuesScreen extends StatefulWidget {
  final String groupId;
  const VenuesScreen({super.key, required this.groupId});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  late final Stream<List<Venue>> _venues = context
      .read<GroupRepository>()
      .watchVenues(widget.groupId);

  Future<void> _edit(Venue? venue) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VenueForm(groupId: widget.groupId, venue: venue),
  );

  Future<void> _delete(Venue venue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('刪除「${venue.name}」？'),
        content: const Text('只會刪除常用場地，已經開出的場次不受影響。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<GroupRepository>().deleteVenue(
        widget.groupId,
        venue.id,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刪除失敗，請稍後重試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthRepository>().currentUser?.id;
    final groups = context.watch<GroupRepository>().groups;
    final group = groups.where((g) => g.id == widget.groupId).firstOrNull;
    final canManage = group?.canManage(userId) ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('常用場地'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add),
                label: const Text('新增'),
              ),
            ),
        ],
      ),
      body: group != null && !group.isMember(userId)
          ? const Center(child: Text('只有球隊成員可以查看常用場地。'))
          : StreamBuilder<List<Venue>>(
              stream: _venues,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('載入場地失敗，請稍後重試。'));
                }
                final venues = snapshot.data;
                if (venues == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (venues.isEmpty) {
                  return Center(
                    child: Text(
                      canManage ? '還沒有常用場地，按右上角「新增」' : '球隊還沒有設定常用場地',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: venues.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final venue = venues[index];
                    return ContentWidth(
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            8,
                            4,
                            8,
                          ),
                          title: Text(
                            venue.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            [
                              '${venue.district} · ${venue.maxPlayers} 人 · ${venue.costLabel}',
                              if (venue.notes.isNotEmpty) venue.notes,
                            ].join('\n'),
                          ),
                          isThreeLine: venue.notes.isNotEmpty,
                          trailing: canManage
                              ? PopupMenuButton<bool>(
                                  tooltip: '${venue.name} 的選項',
                                  onSelected: (delete) =>
                                      delete ? _delete(venue) : _edit(venue),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: false,
                                      child: Text('編輯'),
                                    ),
                                    PopupMenuItem(
                                      value: true,
                                      child: Text('刪除'),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _VenueForm extends StatefulWidget {
  final String groupId;
  final Venue? venue;
  const _VenueForm({required this.groupId, this.venue});

  @override
  State<_VenueForm> createState() => _VenueFormState();
}

class _VenueFormState extends State<_VenueForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.venue?.name ?? '');
  late final _cost = TextEditingController(
    text: widget.venue == null ? '' : '${widget.venue!.cost}',
  );
  late final _players = TextEditingController(
    text: '${widget.venue?.maxPlayers ?? 10}',
  );
  late final _notes = TextEditingController(text: widget.venue?.notes ?? '');
  late String? _city = widget.venue == null
      ? null
      : cityOfDistrict(widget.venue!.district);
  late String? _area = widget.venue == null
      ? null
      : areaOfDistrict(widget.venue!.district);
  late CostMode _costMode = widget.venue?.costMode ?? CostMode.totalVenue;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_name, _cost, _players, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<GroupRepository>().saveVenue(
        widget.groupId,
        Venue(
          id: widget.venue?.id ?? '',
          name: _name.text.trim(),
          city: _city!,
          district: '$_city$_area',
          costMode: _costMode,
          cost: int.parse(_cost.text.trim()),
          maxPlayers: int.parse(_players.text.trim()),
          notes: _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('儲存失敗，請稍後重試。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.venue == null ? '新增常用場地' : '編輯常用場地',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '場地名稱',
                  hintText: '例如：三重運動中心 3F',
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? '請輸入場地名稱' : null,
              ),
              const SizedBox(height: 8),
              DistrictPicker(
                city: _city,
                area: _area,
                onChanged: (city, area) => setState(() {
                  _city = city;
                  _area = area;
                }),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CostMode>(
                segments: const [
                  ButtonSegment(value: CostMode.perPerson, label: Text('每人固定')),
                  ButtonSegment(
                    value: CostMode.totalVenue,
                    label: Text('整場場租平分'),
                  ),
                ],
                selected: {_costMode},
                onSelectionChanged: (value) =>
                    setState(() => _costMode = value.first),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _costMode == CostMode.perPerson
                            ? '每人費用'
                            : '場租',
                        suffixText: '元',
                      ),
                      validator: (value) =>
                          (int.tryParse((value ?? '').trim()) ?? -1) >= 0
                          ? null
                          : '請輸入金額',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _players,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '名額',
                        suffixText: '人',
                      ),
                      validator: (value) =>
                          (int.tryParse((value ?? '').trim()) ?? 0) >= 2
                          ? null
                          : '至少 2 人',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '備註（選填）',
                  hintText: '例如：停車資訊、全場或半場',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '儲存中…' : '儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
