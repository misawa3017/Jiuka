import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../components/ad_banner_widget.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../groups/repositories/group_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';
import '../widgets/event_card.dart';
import '../../../components/content_width.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  int _retryKey = 0;

  void _retry() => setState(() => _retryKey++);

  Future<void> _share(BuildContext context, Event event) async {
    final link = Uri.base.replace(
      path: '/event/${event.id}',
      query: '',
      fragment: '',
    );
    try {
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('場次連結已複製。')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法複製連結，請檢查瀏覽器剪貼簿權限。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventRepository>();
    final auth = context.watch<AuthRepository>();
    final userId = auth.currentUser?.id;
    return StreamBuilder<Event?>(
      key: ValueKey('event-$_retryKey'),
      stream: repository.getEventStream(widget.eventId),
      builder: (context, eventSnapshot) {
        if (eventSnapshot.hasError) {
          return _messagePage('載入場次失敗。', onRetry: _retry);
        }
        if (eventSnapshot.connectionState == ConnectionState.waiting) {
          return _loadingPage();
        }
        final event = eventSnapshot.data;
        if (event == null) return _messagePage('找不到場次');
        if (userId == null) {
          return _EventDetails(
            event: event,
            userId: null,
            participant: null,
            repository: repository,
            onShare: () => _share(context, event),
            onRetry: _retry,
          );
        }
        return StreamBuilder<EventParticipant?>(
          key: ValueKey('participation-$_retryKey'),
          stream: repository.getParticipationStream(widget.eventId, userId),
          builder: (context, participantSnapshot) {
            if (participantSnapshot.hasError) {
              return _messagePage('載入報名狀態失敗。', onRetry: _retry);
            }
            if (participantSnapshot.connectionState ==
                ConnectionState.waiting) {
              return _loadingPage();
            }
            return _EventDetails(
              event: event,
              userId: userId,
              participant: participantSnapshot.data,
              repository: repository,
              onShare: () => _share(context, event),
              onRetry: _retry,
            );
          },
        );
      },
    );
  }

  Scaffold _loadingPage() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Scaffold _messagePage(String message, {VoidCallback? onRetry}) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('重新載入')),
          ],
        ],
      ),
    ),
  );
}

class _EventDetails extends StatelessWidget {
  final Event event;
  final String? userId;
  final EventParticipant? participant;
  final EventRepository repository;
  final VoidCallback onShare;
  final VoidCallback onRetry;

  const _EventDetails({
    required this.event,
    required this.userId,
    required this.participant,
    required this.repository,
    required this.onShare,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isAttending =
        participant?.status == EventParticipationStatus.attending;
    final isWaitlisted =
        participant?.status == EventParticipationStatus.waitlisted;
    final organizerAlreadyPlaying =
        userId != null && event.organizerPlaying && event.organizerId == userId;
    final canJoin = event.canAcceptParticipants(DateTime.now());
    final joining =
        canJoin &&
        !event.isFull &&
        !isAttending &&
        !isWaitlisted &&
        !organizerAlreadyPlaying;
    final estimated = event.estimatedCostPerPerson(joining: joining);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOrganizer = userId == event.organizerId;
    // 系統管理者可管理任何場次：編輯、取消、看名單、移除報名者。
    final isAdmin = context.watch<AuthRepository>().isAdmin;
    final canManage = isOrganizer || isAdmin;
    final time = DateFormat('HH:mm');
    final action = _primaryAction(
      context,
      canJoin: canJoin,
      isAttending: isAttending,
      isWaitlisted: isWaitlisted,
      organizerAlreadyPlaying: organizerAlreadyPlaying,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${event.sport.label}場次'),
        actions: [
          if (kIsWeb)
            IconButton(
              tooltip: '複製場次連結',
              icon: const Icon(Icons.ios_share),
              onPressed: onShare,
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: action == null
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: ContentWidth(
                  child: SizedBox(width: double.infinity, child: action),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (event.status == EventStatus.cancelled)
                  _Banner(
                    icon: Icons.event_busy,
                    text: '主揪已取消此場次',
                    color: scheme.error,
                  )
                else if (!canJoin)
                  _Banner(
                    icon: Icons.lock_clock_outlined,
                    text: '此場次已不開放報名',
                    color: scheme.outline,
                  ),
                if (event.isInviteOnly)
                  _Banner(
                    icon: Icons.lock_outline,
                    text: canManage
                        ? '限熟人中：場次不在首頁，熟人要用連結＋邀請碼報名'
                        : _isTeamMember(context)
                        ? '目前只開放隊員與熟人報名；你是隊員，可以直接報名'
                        : '目前只開放主揪邀請的熟人報名，需要邀請碼',
                    color: scheme.secondary,
                  ),
                if (event.updatedAt case final updatedAt?)
                  _Banner(
                    icon: Icons.update,
                    text:
                        '主揪於 ${DateFormat('MM/dd HH:mm').format(updatedAt)} 更新過場次資訊',
                    color: scheme.primary,
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(event.sport.icon, color: scheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              event.sport.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (isAttending)
                              _StatusChip(
                                label: '你已報名（正取）',
                                color: scheme.primary,
                              )
                            else if (isWaitlisted)
                              _StatusChip(
                                label: '你在候補中',
                                color: scheme.tertiary,
                              )
                            else if (isOrganizer)
                              _StatusChip(
                                label: '你是主揪',
                                color: scheme.secondary,
                              )
                            else if (isAdmin)
                              _StatusChip(label: '管理者', color: scheme.error),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          event.displayTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          text:
                              '${DateFormat('yyyy/MM/dd').format(event.startTime)} ${weekdayLabel(event.startTime)}',
                        ),
                        _InfoRow(
                          icon: Icons.schedule,
                          text:
                              '${time.format(event.startTime)} – ${time.format(event.endTime)}',
                        ),
                        if (event.title.isNotEmpty)
                          _InfoRow(
                            icon: Icons.stadium_outlined,
                            text: event.venue,
                          ),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          text: event.district,
                        ),
                        if (event.organizerName.isNotEmpty)
                          _InfoRow(
                            icon: Icons.person_outline,
                            text: '主揪 ${event.organizerName}',
                          ),
                        if (event.cancelDeadlineHours > 0)
                          _InfoRow(
                            icon: Icons.event_busy_outlined,
                            text:
                                '開始前 ${event.cancelDeadlineHours} 小時內，正取不能自行取消',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _capacityCard(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.payments_outlined,
                          label: event.isCostConfirmed
                              ? '每人費用（已確定）'
                              : event.costMode == CostMode.perPerson
                              ? '每人費用'
                              : '每人預估',
                          value: event.isCostConfirmed
                              ? '${event.finalCostPerPerson} 元'
                              : event.costMode == CostMode.perPerson
                              ? '${event.cost} 元'
                              : estimated == null
                              ? '待估算'
                              : '約 $estimated 元',
                          valueColor: event.isCostConfirmed
                              ? scheme.primary
                              : null,
                          note: event.isCostConfirmed
                              ? '主揪已確定最終金額'
                              : event.costMode == CostMode.perPerson
                              ? '固定費用'
                              : '整場場租 ${event.cost} 元，依確定人數平分，最終金額由主揪於開始後確定',
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '主揪補充說明',
                    icon: Icons.notes,
                    children: [Text(event.description)],
                  ),
                ],
                // 場次開始後（未取消）由主揪或管理者確定每人最終費用。
                if (canManage &&
                    event.status != EventStatus.cancelled &&
                    !event.startTime.isAfter(DateTime.now())) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '費用結算',
                    icon: Icons.request_quote_outlined,
                    children: [
                      Text(
                        event.isCostConfirmed
                            ? '已確定每人 ${event.finalCostPerPerson} 元，正取球友已收到通知。'
                            : '確定後會通知正取球友，可再修改。',
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _confirmCost(context),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          event.isCostConfirmed ? '修改最終費用' : '確定每人費用',
                        ),
                      ),
                    ],
                  ),
                ],
                if (canManage && canJoin) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: isOrganizer ? '主揪管理' : '管理者操作',
                    icon: Icons.manage_accounts_outlined,
                    children: [
                      if (event.isInviteOnly)
                        _InvitePanel(event: event, repository: repository),
                      _OrganizerActions(event: event, repository: repository),
                    ],
                  ),
                ],
                if (canManage) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '正取與候補名單',
                    icon: Icons.groups_outlined,
                    children: [
                      _OrganizerRoster(
                        stream: repository.getParticipantsStream(event.id),
                        onRetry: onRetry,
                        // 主揪與管理者可移除報名者，且場次仍開放時才有意義。
                        onRemove: canManage && canJoin
                            ? (participant) =>
                                  _confirmRemove(context, participant)
                            : null,
                        // 已取消的場次不需要記錄出席與收款。
                        onMark: event.status == EventStatus.cancelled
                            ? null
                            : (participant, {attended, paid}) =>
                                  _mark(context, participant, attended, paid),
                      ),
                    ],
                  ),
                ],
                if (kIsWeb) ...[
                  const SizedBox(height: 24),
                  const AdBannerWidget(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _capacityCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = event.maxPlayers == 0
        ? 0.0
        : (event.occupiedCount / event.maxPlayers).clamp(0.0, 1.0);
    final notes = [
      if (event.organizerPlaying)
        event.existingPlayers > 1
            ? '含主揪與已約 ${event.existingPlayers - 1} 人'
            : '含主揪本人'
      else if (event.existingPlayers > 0)
        '含已約 ${event.existingPlayers} 人',
      if (event.waitlistCount > 0) '候補 ${event.waitlistCount} 人',
    ];
    return _StatCard(
      icon: Icons.group_outlined,
      label: '名額 ${event.occupiedCount} / ${event.maxPlayers}',
      value: event.isFull ? '已額滿' : '尚缺 ${event.spotsLeft} 人',
      valueColor: event.isFull ? scheme.tertiary : scheme.primary,
      note: notes.isEmpty ? null : notes.join(' · '),
      extra: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: scheme.surfaceContainerHighest,
          color: event.isFull ? scheme.tertiary : scheme.primary,
        ),
      ),
    );
  }

  /// 報名前選擇同行朋友人數（限熟人場次另外輸入邀請碼），並預告整組會進正取還是候補。
  /// 目前使用者是不是這個球隊場次的隊員（限熟人階段可免邀請碼）。
  bool _isTeamMember(BuildContext context) {
    if (event.groupId.isEmpty || userId == null) return false;
    final group = context
        .read<GroupRepository>()
        .groups
        .where((g) => g.id == event.groupId)
        .firstOrNull;
    return group?.isMember(userId) ?? false;
  }

  Future<(int, String?)?> _pickGuests(BuildContext context) {
    // 球隊場次的隊員不用輸入邀請碼。
    final needsCode = event.isInviteOnly && !_isTeamMember(context);
    var guests = 0;
    // 不在這裡 dispose：對話框關閉動畫期間 TextField 仍在使用。
    final codeController = TextEditingController();
    return showDialog<(int, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final party = 1 + guests;
          final fits = event.fitsParty(party);
          return AlertDialog(
            title: const Text('報名'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (needsCode) ...[
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '邀請碼',
                      helperText: '目前只開放熟人報名，請輸入主揪給你的 6 位數邀請碼',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                ],
                const Text('有朋友跟你一起來嗎？朋友不用註冊，會和你一起占名額。'),
                const SizedBox(height: 12),
                // 用可換行的選項標籤，手機寬度下文字不會被擠成直排。
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var n = 0; n <= EventParticipant.maxGuests; n++)
                      ChoiceChip(
                        label: Text(n == 0 ? '只有我' : '+$n 位朋友'),
                        selected: guests == n,
                        onSelected: (_) => setState(() => guests = n),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  fits
                      ? '共 $party 人，可以直接進正取。'
                      : event.waitlistCount > 0
                      ? '共 $party 人。目前已有人候補，會排在候補名單，依順序整組遞補。'
                      : '共 $party 人，名額只剩 ${event.spotsLeft} 位，會整組進入候補。',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed:
                    needsCode &&
                        !RegExp(r'^\d{6}$').hasMatch(codeController.text.trim())
                    ? null
                    : () => Navigator.pop(dialogContext, (
                        guests,
                        needsCode ? codeController.text.trim() : null,
                      )),
                child: Text(fits ? '確認報名' : '加入候補'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCost(BuildContext context) async {
    final controller = TextEditingController(
      text: '${event.finalCostPerPerson ?? event.suggestedFinalCost}',
    );
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確定每人費用'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.costMode == CostMode.perPerson
                  ? '原訂每人 ${event.cost} 元，可依實際情況調整。'
                  : '場租 ${event.cost} 元 ÷ ${event.occupiedCount} 人，'
                        '無條件進位為 ${event.suggestedFinalCost} 元，可自行調整。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每人費用',
                suffixText: '元',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
    // 不立即 dispose：對話框關閉動畫期間 TextField 仍在使用 controller。
    if (amount == null || !context.mounted) return;
    try {
      await repository.confirmCost(event.id, amount);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('確定費用失敗，請稍後重試。')));
      }
    }
  }

  Future<void> _mark(
    BuildContext context,
    EventParticipant participant,
    bool? attended,
    bool? paid,
  ) async {
    try {
      await repository.markParticipant(
        event.id,
        participant.userId,
        attended: attended,
        paid: paid,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('記錄失敗，請稍後重試。')));
      }
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    EventParticipant participant,
  ) async {
    final name = participant.displayName.isEmpty
        ? '這位球友'
        : participant.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('把 $name 移出名單？'),
        content: Text(
          participant.status == EventParticipationStatus.attending
              ? '移除後若有候補，第一位候補會自動遞補。目前沒有通知功能，請自行告知對方。'
              : '移除後對方將不在候補名單中。目前沒有通知功能，請自行告知對方。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確認移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.removeParticipant(event.id, participant.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已將 $name 移出名單。')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('移除失敗，請稍後重試。')));
      }
    }
  }

  /// 底部固定的主要操作；沒有可做的操作時回傳 null。
  Widget? _primaryAction(
    BuildContext context, {
    required bool canJoin,
    required bool isAttending,
    required bool isWaitlisted,
    required bool organizerAlreadyPlaying,
  }) {
    if (!canJoin) return null;
    if (userId == null) {
      return FilledButton.icon(
        onPressed: () => context.push(
          '/login?from=${Uri.encodeComponent('/event/${event.id}')}',
        ),
        icon: const Icon(Icons.login),
        label: const Text('使用 Google 登入後報名'),
      );
    }
    if (organizerAlreadyPlaying) return null;
    if (isAttending && event.isPastCancelDeadline(DateTime.now())) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('已超過取消期限，請聯絡主揪'),
      );
    }
    if (isAttending || isWaitlisted) {
      return OutlinedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(isWaitlisted ? '取消候補？' : '取消報名？'),
              content: const Text('取消後名額與預估費用可能變動。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('返回'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('確認取消'),
                ),
              ],
            ),
          );
          if (confirmed != true || !context.mounted) return;
          try {
            await repository.leaveEvent(event.id, userId!);
          } on FirebaseFunctionsException catch (error) {
            // 例如剛好超過取消期限：顯示伺服器的說明。
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error.message ?? '取消失敗，請稍後重試。')),
              );
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('取消失敗，請稍後重試。')));
            }
          }
        },
        child: Text(isWaitlisted ? '取消候補' : '取消報名'),
      );
    }
    return FilledButton.icon(
      onPressed: () async {
        final choice = await _pickGuests(context);
        if (choice == null || !context.mounted) return;
        final (guests, inviteCode) = choice;
        try {
          final user = context.read<AuthRepository>().currentUser!;
          await repository.joinEvent(
            event.id,
            user.id,
            user.name,
            guests: guests,
            inviteCode: inviteCode,
          );
        } on FirebaseException catch (error) {
          if (context.mounted) {
            // 限熟人場次被拒絕，最常見的原因是邀請碼錯誤。
            final message =
                event.isInviteOnly && error.code == 'permission-denied'
                ? '邀請碼不正確，請向主揪確認。'
                : '報名失敗，請稍後重試。';
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('報名失敗，請稍後重試。')));
          }
        }
      },
      icon: Icon(event.fitsParty(1) ? Icons.how_to_reg : Icons.hourglass_empty),
      label: Text(event.fitsParty(1) ? '我要報名' : '加入候補'),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Banner({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? note;
  final Widget? extra;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.note,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (extra != null) ...[const SizedBox(height: 10), extra!],
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 限熟人場次：顯示邀請碼、複製「連結＋邀請碼」、開放公開報名。
class _InvitePanel extends StatefulWidget {
  final Event event;
  final EventRepository repository;
  const _InvitePanel({required this.event, required this.repository});

  @override
  State<_InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<_InvitePanel> {
  late final Future<String?> _code = widget.repository.getInviteCode(
    widget.event.id,
  );
  bool _publishing = false;

  Future<void> _copy(String code) async {
    final link = Uri.base.replace(
      path: '/event/${widget.event.id}',
      query: '',
      fragment: '',
    );
    final text =
        '${widget.event.displayTitle}\n'
        '報名連結：$link\n'
        '邀請碼：$code';
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已複製連結與邀請碼，可以貼到群組了。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法複製，請手動抄下邀請碼。')));
      }
    }
  }

  Future<void> _publish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('開放公開報名？'),
        content: const Text('開放後場次會出現在首頁，任何人都能報名，不再需要邀請碼。這個動作無法改回限熟人。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('開放'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _publishing = true);
    try {
      await widget.repository.publishEvent(widget.event.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('開放失敗，請稍後重試。')));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String?>(
      future: _code,
      builder: (context, snapshot) {
        final code = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('邀請碼', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    code ??
                        (snapshot.connectionState == ConnectionState.waiting
                            ? '載入中…'
                            : '無法載入'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: code == null ? null : () => _copy(code),
                    icon: const Icon(Icons.copy),
                    label: const Text('複製邀請'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _publishing ? null : _publish,
                    icon: const Icon(Icons.public),
                    label: Text(_publishing ? '處理中…' : '開放公開報名'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _OrganizerActions extends StatelessWidget {
  final Event event;
  final EventRepository repository;

  const _OrganizerActions({required this.event, required this.repository});

  Future<void> _cancel(BuildContext context) async {
    final signedUp = event.attendeeCount + event.waitlistCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消整個場次？'),
        content: Text(
          signedUp > 0
              ? '已有 $signedUp 位球友報名或候補。取消後無法復原，'
                    '目前沒有通知功能，請自行告知他們。'
              : '取消後無法復原，場次將不再接受報名。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確認取消場次'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.cancelEvent(event.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('取消場次失敗，請稍後重試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('編輯場次'),
            onPressed: () => context.push('/event/${event.id}/edit'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextButton.icon(
            icon: const Icon(Icons.event_busy),
            label: const Text('取消場次'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _cancel(context),
          ),
        ),
      ],
    );
  }
}

class _OrganizerRoster extends StatelessWidget {
  final Stream<List<EventParticipant>> stream;
  final VoidCallback onRetry;
  final void Function(EventParticipant participant)? onRemove;
  final void Function(
    EventParticipant participant, {
    bool? attended,
    bool? paid,
  })?
  onMark;

  const _OrganizerRoster({
    required this.stream,
    required this.onRetry,
    this.onRemove,
    this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventParticipant>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('名單載入失敗。'),
              OutlinedButton(onPressed: onRetry, child: const Text('重新載入名單')),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          );
        }
        final attendees = snapshot.data!
            .where((p) => p.status == EventParticipationStatus.attending)
            .toList();
        final waitlist = snapshot.data!
            .where((p) => p.status == EventParticipationStatus.waitlisted)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RosterHeading(
              label: '正取',
              count: attendees.fold(0, (total, p) => total + p.partySize),
              extra: attendees.isEmpty
                  ? null
                  : '到場 ${attendees.where((p) => p.attended).length}'
                        ' · 已付 ${attendees.where((p) => p.paid).length}',
            ),
            _Roster(users: attendees, onRemove: onRemove, onMark: onMark),
            const SizedBox(height: 12),
            _RosterHeading(
              label: '候補',
              count: waitlist.fold(0, (total, p) => total + p.partySize),
            ),
            _Roster(users: waitlist, onRemove: onRemove),
          ],
        );
      },
    );
  }
}

class _RosterHeading extends StatelessWidget {
  final String label;
  final int count;
  final String? extra;
  const _RosterHeading({required this.label, required this.count, this.extra});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        extra == null ? '$label $count 人' : '$label $count 人 · $extra',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Roster extends StatelessWidget {
  final List<EventParticipant> users;
  final void Function(EventParticipant participant)? onRemove;

  /// 有值時（正取名單）顯示「到場」「已付」標記，點一下切換。
  final void Function(
    EventParticipant participant, {
    bool? attended,
    bool? paid,
  })?
  onMark;
  const _Roster({required this.users, this.onRemove, this.onMark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('目前沒有球友', style: TextStyle(color: scheme.outline)),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < users.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(
                users[index].displayName.isEmpty
                    ? '${index + 1}'
                    : users[index].displayName.characters.first,
              ),
            ),
            title: Text(
              [
                users[index].displayName.isEmpty
                    ? '球友 ${index + 1}'
                    : users[index].displayName,
                if (users[index].guests > 0) '+${users[index].guests}',
              ].join(' '),
            ),
            subtitle: onMark == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('到場'),
                          selected: users[index].attended,
                          onSelected: (value) =>
                              onMark!(users[index], attended: value),
                        ),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('已付'),
                          selected: users[index].paid,
                          onSelected: (value) =>
                              onMark!(users[index], paid: value),
                        ),
                      ],
                    ),
                  ),
            trailing: onRemove == null
                ? Text('#${index + 1}', style: TextStyle(color: scheme.outline))
                : IconButton(
                    tooltip: '移出名單',
                    icon: Icon(
                      Icons.person_remove_outlined,
                      color: scheme.error,
                    ),
                    onPressed: () => onRemove!(users[index]),
                  ),
          ),
      ],
    );
  }
}
