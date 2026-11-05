import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/outbound_media.dart';
import '../providers/conversation_workflow_provider.dart';
import '../providers/inbox_providers.dart';
import '../providers/inbox_send_provider.dart';
import '../widgets/cancel_message_button.dart';
import '../widgets/conversation_badge.dart';
import '../widgets/conversation_workflow_sheet.dart';
import '../widgets/handoff_request_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_media_view.dart';
import '../widgets/service_window_note.dart';
import '../widgets/tag_editor_sheet.dart';

/// Lets the wide inbox layout ask the chat shown beside the list whether it may be
/// replaced (an unsent draft or an unsettled send needs confirmation first).
class ChatLeaveGuard {
  Object? _owner;
  Future<bool> Function()? _check;

  /// True when nothing would be lost, or the employee agreed to leave the chat.
  Future<bool> confirmLeave() => _check?.call() ?? Future.value(true);

  void _attach(Object owner, Future<bool> Function() check) {
    _owner = owner;
    _check = check;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _check = null;
  }
}

/// One conversation: header with status and workflow actions, messages from the
/// newest, and the composer. Pushed as its own route on phones; with a
/// [leaveGuard] it renders beside the list on wide screens.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation, this.leaveGuard});

  final Conversation conversation;

  /// Set when the chat is embedded beside the list; null for a pushed route.
  final ChatLeaveGuard? leaveGuard;

  bool get embedded => leaveGuard != null;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

const _cancellableStates = {'queued', 'leased', 'retry_wait', 'blocked'};

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  late final String? _tenantId;
  late final String? _userId;
  bool _scopeInvalidated = false;
  bool _allowExit = false;
  VoidCallback? _unwatch;
  List<String> _tagSuggestions = const [];

  InboxSendScope get _sendScope =>
      (tenantId: _tenantId ?? '', conversationId: widget.conversation.id);

  InboxSendController get _sendController =>
      ref.read(inboxSendProvider(_sendScope).notifier);

  @override
  void initState() {
    super.initState();
    _tenantId = ref.read(selectedTenantProvider)?.id;
    _userId = ref.read(authControllerProvider).value?.userId;
    if (_tenantId != null) {
      // A send that is still being checked keeps its frozen text across reopening.
      final frozen = _sendController.pendingText;
      if (frozen != null) _controller.text = frozen;
    }
    widget.leaveGuard?._attach(this, _confirmSwitch);
    _unwatch = ref.read(inboxRealtimeProvider).watchMessages(
          widget.conversation.id,
          onMessages: () {
            if (!mounted || _scopeInvalidated) return;
            ref.invalidate(messagesProvider(widget.conversation.id));
            ref.invalidate(conversationsProvider);
          },
          onMedia: () {
            if (!mounted || _scopeInvalidated) return;
            ref.invalidate(messagesProvider(widget.conversation.id));
          },
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markConversationOpened();
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leaveGuard != widget.leaveGuard) {
      oldWidget.leaveGuard?._detach(this);
      widget.leaveGuard?._attach(this, _confirmSwitch);
    }
  }

  @override
  void dispose() {
    widget.leaveGuard?._detach(this);
    _controller.dispose();
    _unwatch?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = _tenantId;
    if (tenantId == null ||
        _userId == null ||
        ref.watch(selectedTenantProvider)?.id != tenantId ||
        ref.watch(authControllerProvider).value?.userId != _userId) {
      _scopeInvalidated = true;
    }
    if (_scopeInvalidated || tenantId == null) return _invalidatedView(context);

    final c = FlowColors.of(context);
    final sendState = ref.watch(inboxSendProvider(_sendScope));
    final messages = ref.watch(messagesProvider(widget.conversation.id));
    final conversations = ref.watch(conversationsProvider);
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final canHandoff = membership?.hasPermission('handoff') ?? false;
    final scope = (
      tenantId: tenantId,
      conversationId: widget.conversation.id,
      userId: _userId!
    );
    final conversation = conversations.maybeWhen(
      data: (items) => items.firstWhere(
        (item) => item.id == widget.conversation.id,
        orElse: () => widget.conversation,
      ),
      orElse: () => widget.conversation,
    );

    conversations.whenData((items) {
      final tags = <String>{};
      for (final item in items) {
        tags.addAll(item.tags);
      }
      _tagSuggestions = tags.toList()..sort();
    });

    final wide = MediaQuery.sizeOf(context).width >= 600;
    final actions = _headerActions(
      context,
      wide: widget.embedded && wide,
      scope: scope,
      sendState: sendState,
      conversation: conversation,
      canHandoff: canHandoff,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          Container(
            padding: const EdgeInsets.fromLTRB(FlowSpace.xl - 4, FlowSpace.md, FlowSpace.md, FlowSpace.md),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              Expanded(child: _ChatTitle(conversation: conversation, userId: _userId, large: true)),
              const SizedBox(width: FlowSpace.sm),
              ...actions,
            ]),
          ),
        _OpenedLine(conversation: conversation),
        Expanded(
          child: messages.when(
            data: (items) => items.isEmpty
                ? const _CenteredState(
                    child: EmptyState(
                      compact: true,
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Henüz mesaj yok',
                      message: 'Müşteri yazdığında mesajlar burada görünür.',
                    ),
                  )
                : _MessageList(
                    messages: items,
                    userId: _userId,
                    scope: scope,
                    isAdmin: membership?.isAdmin ?? false,
                  ),
            error: (_, __) => _CenteredState(
              child: ErrorState(
                title: 'Mesajlar yüklenemedi',
                onRetry: () => ref.invalidate(messagesProvider(widget.conversation.id)),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
        if (sendState.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(FlowSpace.md, FlowSpace.sm, FlowSpace.md, 0),
            child: InboxNotice(
              sendState.error!,
              tone: sendState.locked ? FlowTone.warning : FlowTone.danger,
            ),
          ),
        _composer(context, sendState, conversation),
      ],
    );

    if (widget.embedded) return Material(color: c.canvas, child: body);

    return PopScope<Object?>(
        canPop: _allowExit ||
            (!sendState.locked && _controller.text.trim().isEmpty),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmLeave(sendState);
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: (ModalRoute.of(context)?.canPop ?? false) ? 0 : FlowSpace.lg,
            toolbarHeight: 64,
            title: _ChatTitle(conversation: conversation, userId: _userId),
            actions: [...actions, const SizedBox(width: 4)],
          ),
          body: SafeArea(top: false, child: body),
        ));
  }

  Widget _invalidatedView(BuildContext context) {
    const state = _CenteredState(
      child: EmptyState(
        compact: true,
        icon: Icons.lock_reset_rounded,
        title: 'Oturum veya işletme değişti',
        message: 'Gelen kutusundan bir konuşmayı yeniden açın.',
      ),
    );
    if (widget.embedded) return Material(color: FlowColors.of(context).canvas, child: state);
    return Scaffold(appBar: AppBar(title: const Text('Konuşma')), body: state);
  }

  List<Widget> _headerActions(
    BuildContext context, {
    required bool wide,
    required ConversationScope scope,
    required InboxSendState sendState,
    required Conversation conversation,
    required bool canHandoff,
  }) {
    final manage = sendState.busy || sendState.locked
        ? null
        : () => showConversationWorkflow(context, scope);
    void refresh() {
      ref.invalidate(messagesProvider(widget.conversation.id));
      ref.invalidate(conversationsProvider);
    }

    final handoffEnabled = canHandoff &&
        !sendState.locked &&
        conversation.status != ConversationStatus.closed;
    return [
      if (wide)
        OutlinedButton.icon(
          onPressed: manage,
          icon: const Icon(Icons.manage_accounts_outlined, size: 18),
          label: const Text('Konuşmayı yönet'),
        )
      else
        IconButton(
          tooltip: 'Konuşmayı yönet',
          icon: const Icon(Icons.manage_accounts_outlined),
          onPressed: manage,
        ),
      if (wide) ...[
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Konuşmayı yenile',
          icon: const Icon(Icons.refresh),
          onPressed: refresh,
        ),
      ],
      PopupMenuButton<String>(
        tooltip: 'Diğer konuşma işlemleri',
        icon: const Icon(Icons.more_horiz),
        onSelected: (value) {
          if (value == 'tags') _openTagEditor(conversation);
          if (value == 'handoff') _openHandoverSheet();
          if (value == 'refresh') refresh();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'tags', child: Text('Etiketleri düzenle')),
          PopupMenuItem(
              value: 'handoff',
              enabled: handoffEnabled,
              child: const Text('Temsilciye aktar')),
          if (!wide) const PopupMenuItem(value: 'refresh', child: Text('Konuşmayı yenile')),
        ],
      ),
    ];
  }

  Widget _composer(BuildContext context, InboxSendState sendState, Conversation conversation) {
    final c = FlowColors.of(context);
    final pendingMedia = sendState.locked && _sendController.hasPendingMedia;
    final lastCustomer = conversation.lastCustomerMessageAt;
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowRadius.panel),
          borderSide: BorderSide(color: color, width: width),
        );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, FlowSpace.sm + 2, FlowSpace.md, FlowSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (lastCustomer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(FlowSpace.sm, 0, 0, FlowSpace.sm + 2),
            child: ServiceWindowNote(lastCustomerMessageAt: lastCustomer),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            onPressed: sendState.busy
                ? null
                : pendingMedia
                    ? _discardMedia
                    : sendState.locked
                        ? null
                        : _pickMedia,
            tooltip: pendingMedia ? 'Bekleyen dosyayı kaldır' : 'Fotoğraf veya belge gönder',
            icon: Icon(pendingMedia ? Icons.close : Icons.attach_file, color: c.muted),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: sendState.locked,
              onChanged: (_) => setState(() => _allowExit = false),
              maxLength: 4096,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                  currentLength < 3600
                      ? null
                      : Text('$currentLength / $maxLength', style: FlowText.mono(context, size: 11)),
              decoration: InputDecoration(
                hintText: 'Yanıt yazın',
                isDense: true,
                filled: true,
                fillColor: sendState.locked ? c.raised : c.canvas,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: border(c.borderStrong),
                enabledBorder: border(c.borderStrong),
                disabledBorder: border(c.border),
                focusedBorder: border(c.isDark ? c.lime : c.accentText, 2),
              ),
            ),
          ),
          const SizedBox(width: FlowSpace.sm),
          IconButton.filled(
            tooltip: sendState.locked ? 'Aynı isteği tekrar kontrol et' : 'Gönder',
            onPressed: sendState.busy ? null : _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: c.lime,
              foregroundColor: c.onLime,
              disabledBackgroundColor: c.raised,
              disabledForegroundColor: c.faint,
              minimumSize: const Size(44, 44),
              shape: const CircleBorder(),
              side: c.isDark ? BorderSide.none : BorderSide(color: c.limeEdge),
            ),
            icon: sendState.busy
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.muted),
                  )
                : Icon(sendState.locked ? Icons.refresh : Icons.send_rounded, size: 20),
          ),
        ]),
      ]),
    );
  }

  Future<bool> _askToLeave(bool locked) => confirmAction(
        context,
        title: 'Konuşmadan çıkılsın mı?',
        message: locked
            ? 'Gönderim sunucuda devam ediyor olabilir. Sonucu gelen kutusundan kontrol edebilirsiniz.'
            : 'Yazdığınız mesaj taslağı silinecek.',
        confirmLabel: 'Çık',
        cancelLabel: 'Konuşmada kal',
        destructive: true,
      );

  Future<void> _confirmLeave(InboxSendState sendState) async {
    if (sendState.busy) {
      showAppSnack(context, 'Gönderim isteğinin sonucunu bekleyin.');
      return;
    }
    final leave = await _askToLeave(sendState.locked);
    if (!leave || !mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Asked by the wide layout before it shows another conversation in this pane.
  Future<bool> _confirmSwitch() async {
    if (!mounted || _scopeInvalidated || _tenantId == null) return true;
    final sendState = ref.read(inboxSendProvider(_sendScope));
    if (!sendState.locked && _controller.text.trim().isEmpty) return true;
    if (sendState.busy) {
      showAppSnack(context, 'Gönderim isteğinin sonucunu bekleyin.');
      return false;
    }
    final leave = await _askToLeave(sendState.locked);
    return leave && mounted;
  }

  void _discardMedia() => _sendController.discardMedia();

  Future<void> _pickMedia() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FlowSpace.sm, 0, FlowSpace.sm, FlowSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Fotoğraf'),
              subtitle: const Text('JPG veya PNG, en fazla 5 MB'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Belge'),
              subtitle: const Text('PDF, Word, Excel veya TXT, en fazla 16 MB'),
              onTap: () => Navigator.of(context).pop('document'),
            ),
          ]),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == 'image' ? imageExtensions : documentExtensions,
      withData: true,
    );
    final picture = picked?.files.single;
    if (picture?.bytes == null || !mounted) return;
    final checked = outboundMediaFor(fileName: picture!.name, bytes: picture.bytes!);
    if (checked.file == null) {
      showAppSnack(context, checked.error!, error: true);
      return;
    }
    final caption = TextEditingController(text: _controller.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final c = FlowColors.of(context);
        final file = checked.file!;
        return AlertDialog(
          title: Text(file.kind == 'image' ? 'Fotoğraf gönder' : 'Belge gönder'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (file.kind == 'image')
                ClipRRect(
                  borderRadius: FlowRadius.controlAll,
                  child: Image.memory(file.bytes, height: 160, fit: BoxFit.cover),
                )
              else
                Container(
                  padding: const EdgeInsets.all(FlowSpace.md),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: FlowRadius.controlAll,
                    border: Border.all(color: c.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.description_outlined, color: c.muted),
                    const SizedBox(width: FlowSpace.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(file.fileName,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        Text(formatBytes(file.bytes.length), style: FlowText.mono(context, size: 12)),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: FlowSpace.md),
              TextField(
                controller: caption,
                maxLength: 1024,
                decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Gönder'),
            ),
          ],
        );
      },
    );
    final text = caption.text;
    caption.dispose();
    if (confirmed != true || !mounted || ref.read(selectedTenantProvider)?.id != tenantId) {
      return;
    }
    final sent = await _sendController.sendMedia(checked.file!, caption: text);
    if (!mounted) return;
    if (sent) {
      if (text.trim() == _controller.text.trim()) _controller.clear();
      ref.invalidate(messagesProvider(widget.conversation.id));
      ref.invalidate(conversationsProvider);
    }
  }

  Future<void> _sendMessage() async {
    final tenantId = _tenantId;
    if (tenantId == null || ref.read(selectedTenantProvider)?.id != tenantId) {
      return;
    }
    final queued = await ref
        .read(inboxSendProvider((
          tenantId: tenantId,
          conversationId: widget.conversation.id,
        )).notifier)
        .send(_controller.text);
    if (!mounted || ref.read(selectedTenantProvider)?.id != tenantId) return;
    if (queued) {
      _controller.clear();
      ref.invalidate(messagesProvider(widget.conversation.id));
      ref.invalidate(conversationsProvider);
    }
  }

  void _openTagEditor(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TagEditorSheet(
        initialTags: conversation.tags,
        suggestions: _tagSuggestions,
        onSave: (tags) {
          ref.read(conversationsProvider.notifier).updateTags(
                conversation.id,
                tags,
              );
        },
      ),
    );
  }

  void _openHandoverSheet() {
    final tenantId = _tenantId;
    if (tenantId == null || ref.read(selectedTenantProvider)?.id != tenantId) {
      return;
    }
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => HandoffRequestSheet(
        tenantId: tenantId,
        conversationId: widget.conversation.id,
      ),
    ).then((value) {
      if (value == true &&
          mounted &&
          ref.read(selectedTenantProvider)?.id == tenantId) {
        showAppSnack(context, 'Sohbet temsilciye aktarıldı.');
      }
    });
  }

  Future<void> _markConversationOpened() async {
    if (!mounted) return;
    final tenantId = _tenantId;
    if (tenantId == null || ref.read(selectedTenantProvider)?.id != tenantId) {
      return;
    }
    try {
      await ref.read(inboxRepositoryProvider).markOpened(
            tenantId: tenantId,
            conversationId: widget.conversation.id,
          );
      if (mounted && ref.read(selectedTenantProvider)?.id == tenantId) {
        ref.invalidate(conversationsProvider);
      }
    } catch (_) {
      if (!mounted || ref.read(selectedTenantProvider)?.id != tenantId) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: const Text('Görülme bilgisi kaydedilemedi.'),
        action: SnackBarAction(
            label: 'Tekrar dene', onPressed: _markConversationOpened),
      ));
    }
  }
}

/// Avatar, name, status and the customer's number in mono.
class _ChatTitle extends StatelessWidget {
  const _ChatTitle({required this.conversation, required this.userId, this.large = false});

  final Conversation conversation;
  final String? userId;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = conversation.customerPhone;
    return Row(children: [
      InitialsAvatar(conversation.title, size: large ? 44 : 38),
      const SizedBox(width: FlowSpace.md),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(
              conversation.title,
              style: (large ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 3),
          // The number only shows where it fits next to the status; phones keep the status.
          LayoutBuilder(builder: (context, constraints) {
            final showPhone = phone != null && phone.isNotEmpty && constraints.maxWidth >= 240;
            return Row(children: [
              Flexible(child: ConversationStatusBadge(conversation: conversation, userId: userId)),
              if (showPhone) ...[
                const SizedBox(width: FlowSpace.sm),
                Flexible(
                  child: Text(
                    formatPhone(phone),
                    style: FlowText.mono(context, size: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ]);
          }),
        ]),
      ),
    ]);
  }
}

/// "Görüldü 11:52 · Yönetici": when the shared inbox last opened this conversation.
class _OpenedLine extends StatelessWidget {
  const _OpenedLine({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final openedAt = conversation.lastOpenedAt;
    if (openedAt == null) return const SizedBox.shrink();
    final today = DateUtils.isSameDay(openedAt.toLocal(), DateTime.now());
    final time = today ? formatClock(openedAt) : '${formatDayMonth(openedAt)} ${formatClock(openedAt)}';
    final role = switch (conversation.lastOpenedRole) {
      'admin' => 'Yönetici',
      'user' => 'Temsilci',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(FlowSpace.lg, FlowSpace.sm + 2, FlowSpace.lg, 0),
      child: Center(
        child: ChatSystemNote(
          role == null ? 'Görüldü $time' : 'Görüldü $time · $role',
          icon: Icons.visibility_outlined,
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlowSpace.lg),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child),
        ),
      );
}

/// Messages from the newest at the bottom; the list starts there and grows upwards.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.userId,
    required this.scope,
    required this.isAdmin,
  });

  final List<Message> messages;
  final String? userId;
  final ConversationScope scope;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    // Oldest first with a divider at each new day, then read from the end.
    final entries = <Object>[];
    DateTime? day;
    for (final message in messages) {
      final local = message.sentAt.toLocal();
      final current = DateTime(local.year, local.month, local.day);
      if (day != current) {
        entries.add(local);
        day = current;
      }
      entries.add(message);
    }
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < 600 ? FlowSpace.md + 2 : FlowSpace.xl;
    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: FlowSpace.lg),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        if (entry is DateTime) {
          return ChatDayDivider(entry, key: ValueKey('day-${entry.year}-${entry.month}-${entry.day}'));
        }
        final message = entry as Message;
        final cancellable = !message.isFromCustomer &&
            message.sentBy != null &&
            (message.sentBy == userId || isAdmin) &&
            _cancellableStates.contains(message.outboundState);
        return Padding(
          key: ValueKey(message.id),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MessageBubble(
            message: message,
            mine: message.sentBy != null && message.sentBy == userId,
            footer: cancellable
                ? CancelMessageButton(key: ValueKey('cancel-${message.id}'), scope: scope, messageId: message.id)
                : null,
          ),
        );
      },
    );
  }
}
