import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/group_model.dart';
import '../models/season_model.dart';
import '../repositories/group_repository.dart';

Group? _findGroup(BuildContext context, String groupId) => context
    .watch<GroupRepository>()
    .groups
    .where((g) => g.id == groupId)
    .firstOrNull;

String _money(int value) => NumberFormat.decimalPattern('zh_TW').format(value);

/// 球隊的季租列表。
class SeasonsScreen extends StatefulWidget {
  final String groupId;
  const SeasonsScreen({super.key, required this.groupId});

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  late final Stream<List<Season>> _seasons = context
      .read<GroupRepository>()
      .watchSeasons(widget.groupId);

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthRepository>().currentUser?.id;
    final group = _findGroup(context, widget.groupId);
    final canManage = group?.canManage(userId) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('季租'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/group/${widget.groupId}/seasons/new'),
                icon: const Icon(Icons.add),
                label: const Text('新增季租'),
              ),
            ),
        ],
      ),
      body: group != null && !group.isMember(userId)
          ? const Center(child: Text('只有球隊成員可以查看季租。'))
          : StreamBuilder<List<Season>>(
              stream: _seasons,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('載入季租失敗，請稍後重試。'));
                }
                final seasons = snapshot.data;
                if (seasons == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (seasons.isEmpty) {
                  return Center(
                    child: Text(canManage ? '還沒有季租，按右上角「新增季租」' : '球隊目前沒有季租'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final season = seasons[index];
                    return ContentWidth(
                      child: Card(
                        child: ListTile(
                          title: Text(season.name),
                          subtitle: Text(
                            '${season.venueName} · ${season.weekdayLabel} '
                            '${season.startTime}–${season.endTime}\n'
                            '${season.startDate} – ${season.endDate} · '
                            '季租 ${season.memberIds.length} 人',
                          ),
                          isThreeLine: true,
                          trailing: season.active
                              ? null
                              : const Chip(label: Text('已停用')),
                          onTap: () => context.push(
                            '/group/${widget.groupId}/season/${season.id}',
                          ),
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

/// 季租頁：設定摘要、收支、季租成員與季費繳交、停打日。
class SeasonDetailScreen extends StatefulWidget {
  final String groupId;
  final String seasonId;
  const SeasonDetailScreen({
    super.key,
    required this.groupId,
    required this.seasonId,
  });

  @override
  State<SeasonDetailScreen> createState() => _SeasonDetailScreenState();
}

class _SeasonDetailScreenState extends State<SeasonDetailScreen> {
  late final Stream<Season?> _season = context
      .read<GroupRepository>()
      .watchSeason(widget.groupId, widget.seasonId);

  Future<void> _update(
    Future<void> Function(GroupRepository repo) action,
  ) async {
    try {
      await action(context.read<GroupRepository>());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新失敗，請稍後重試。')));
      }
    }
  }

  Future<void> _editMembers(Group group, Season season) async {
    final selected = {...season.memberIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('季租成員（${selected.length}/${season.capacity}）'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final id in group.memberIds)
                  CheckboxListTile(
                    value: selected.contains(id),
                    title: Text(group.memberNames[id] ?? '成員'),
                    onChanged:
                        !selected.contains(id) &&
                            selected.length >= season.capacity
                        ? null
                        : (checked) => setState(
                            () => checked == true
                                ? selected.add(id)
                                : selected.remove(id),
                          ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    // 依隊員順序保存；不再是季租成員的人，也從已繳名單移除。
    final members = group.memberIds.where(result.contains).toList();
    await _update(
      (repo) => repo.updateSeason(
        widget.groupId,
        widget.seasonId,
        memberIds: members,
        paidMemberIds: season.paidMemberIds.where(result.contains).toList(),
      ),
    );
  }

  Future<void> _addSkipDate(Season season) async {
    final start = DateTime.tryParse(season.startDate) ?? DateTime.now();
    final end = DateTime.tryParse(season.endDate) ?? start;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: start,
      lastDate: end,
      helpText: '選擇停打日期',
    );
    if (picked == null) return;
    final date = Season.formatDate(picked);
    if (season.skipDates.contains(date)) return;
    await _update(
      (repo) => repo.updateSeason(
        widget.groupId,
        widget.seasonId,
        skipDates: [...season.skipDates, date]..sort(),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除這個季租？'),
        content: const Text('之後不會再自動開場次；已經開出的場次不受影響。'),
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
    await _update((repo) => repo.deleteSeason(widget.groupId, widget.seasonId));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthRepository>().currentUser?.id;
    final group = _findGroup(context, widget.groupId);
    final canManage = group?.canManage(userId) ?? false;
    final theme = Theme.of(context);

    return StreamBuilder<Season?>(
      stream: _season,
      builder: (context, snapshot) {
        final season = snapshot.data;
        if (group == null || season == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('季租')),
            body: Center(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : const Text('找不到這個季租，或你不是球隊成員。'),
            ),
          );
        }
        final balance = season.collectedFees - season.totalRent;
        return Scaffold(
          appBar: AppBar(
            title: Text(season.name),
            actions: [
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: '季租選項',
                  onSelected: (value) => switch (value) {
                    'edit' => context.push(
                      '/group/${widget.groupId}/season/${widget.seasonId}/edit',
                    ),
                    _ => _delete(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('編輯設定')),
                    PopupMenuItem(value: 'delete', child: Text('刪除季租')),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionCard(
                      title:
                          '${season.venueName} · ${season.weekdayLabel} '
                          '${season.startTime}–${season.endTime}',
                      icon: Icons.stadium_outlined,
                      children: [
                        Text(
                          [
                            '${season.startDate} – ${season.endDate}，共 ${season.playDates.length} 場',
                            '容納 ${season.capacity} 人 · 季租 ${season.memberIds.length} 人 · '
                                '每週臨打 ${season.capacity - season.memberIds.length} 位',
                            '臨打每人 ${season.dropInFee} 元 · '
                                '${season.dropInMode == 'inviteOnly' ? '先開放給隊員與熟人' : '公開臨打'}',
                            '提前 ${season.openDaysBefore} 天開出場次 · 負責主揪 '
                                '${group.memberNames[season.organizerId] ?? '成員'}',
                          ].join('\n'),
                          style: TextStyle(
                            height: 1.7,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (canManage)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('自動開出每週場次'),
                            value: season.active,
                            onChanged: (value) => _update(
                              (repo) => repo.updateSeason(
                                widget.groupId,
                                widget.seasonId,
                                active: value,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.2,
                      children: [
                        _Figure(label: '整季場租', value: _money(season.totalRent)),
                        _Figure(
                          label:
                              '已收季費 ${season.paidMemberIds.length}/${season.memberIds.length}',
                          value: _money(season.collectedFees),
                          highlight: true,
                        ),
                        const _Figure(label: '臨打收入（已付）', value: '開打後統計'),
                        _Figure(
                          label: '目前差額',
                          value: balance >= 0
                              ? '+${_money(balance)}'
                              : '−${_money(-balance)}',
                          warning: balance < 0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '季租成員 ${season.memberIds.length} 人',
                      icon: Icons.groups_outlined,
                      children: [
                        Text(
                          '每人季費 ${_money(season.feePerMember)} 元'
                          '${season.suggestedFee == null ? '' : '（場租 ÷ ${season.memberIds.length} ≈ ${_money(season.suggestedFee!)}）'}',
                          style: theme.textTheme.bodySmall,
                        ),
                        for (final id in season.memberIds)
                          Row(
                            children: [
                              Expanded(
                                child: Text(group.memberNames[id] ?? '成員'),
                              ),
                              FilterChip(
                                label: Text(
                                  season.paidMemberIds.contains(id)
                                      ? '已繳'
                                      : '未繳',
                                ),
                                selected: season.paidMemberIds.contains(id),
                                onSelected: canManage
                                    ? (paid) => _update(
                                        (repo) => repo.updateSeason(
                                          widget.groupId,
                                          widget.seasonId,
                                          paidMemberIds: paid
                                              ? [...season.paidMemberIds, id]
                                              : season.paidMemberIds
                                                    .where((p) => p != id)
                                                    .toList(),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        if (canManage)
                          OutlinedButton.icon(
                            onPressed: () => _editMembers(group, season),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('編輯季租成員'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '停打日期',
                      icon: Icons.event_busy_outlined,
                      children: [
                        if (season.skipDates.isEmpty)
                          Text(
                            '沒有停打日',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final date in season.skipDates)
                              InputChip(
                                label: Text(date),
                                onDeleted: canManage
                                    ? () => _update(
                                        (repo) => repo.updateSeason(
                                          widget.groupId,
                                          widget.seasonId,
                                          skipDates: season.skipDates
                                              .where((d) => d != date)
                                              .toList(),
                                        ),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                        if (canManage)
                          OutlinedButton.icon(
                            onPressed: () => _addSkipDate(season),
                            icon: const Icon(Icons.add),
                            label: const Text('新增停打日'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool warning;
  const _Figure({
    required this.label,
    required this.value,
    this.highlight = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warning
        ? scheme.error
        : highlight
        ? scheme.primary
        : scheme.onSurface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
