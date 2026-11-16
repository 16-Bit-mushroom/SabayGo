import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/layout/review_counts.dart';
import '../../../core/network/api_client.dart';
import '../../../data/repositories/messaging_repository.dart';
import '../../../viewmodels/messaging_provider.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';

/// The A2Z office's shared inbox: every passenger and Dispatcher thread
/// with the office lands here, and any signed-in office
/// staff member can pick one up and reply (see the "office" kind in
/// backend/app/application/messaging/service.py). A specific staff member
/// never "owns" a thread the way a 1:1 chat would.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final MessagingProvider _provider;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _provider = MessagingProvider(MessagingRepository(context.read<ApiClient>()));
  }

  @override
  void dispose() {
    _provider.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MessagingProvider>.value(
      value: _provider,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Messages',
              description: 'Chat with crew and passengers. Your replies are sent as the '
                  'cooperative office. You can edit or delete a message you sent.',
              actions: [
                FilledButton.icon(
                  onPressed: () => _newMessage(context),
                  icon: const Icon(Icons.edit_square, size: 18),
                  label: const Text('New message'),
                ),
                RefreshButton(onPressed: _provider.refreshConversations),
              ],
            ),
            Expanded(
              child: Panel(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    const SizedBox(width: 340, child: _ConversationList()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _Thread(textController: _textController)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _MessagesScreenState {
  Future<void> _newMessage(BuildContext context) async {
    final picked = await showDialog<ConsoleContact>(
      context: context,
      builder: (_) => _NewMessageDialog(load: _provider.contacts),
    );
    if (picked == null) return;
    final err = await _provider.startWith(picked.userId);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

/// "New message": choose a Dispatcher, or a passenger with a seat this
/// week, and the thread opens (an existing one if there is one).
class _NewMessageDialog extends StatefulWidget {
  const _NewMessageDialog({required this.load});

  final Future<List<ConsoleContact>> Function() load;

  @override
  State<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends State<_NewMessageDialog> {
  late final Future<List<ConsoleContact>> _future = widget.load();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search by name',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: FutureBuilder<List<ConsoleContact>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Could not load names.\n${snap.error}', textAlign: TextAlign.center));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                final rows = [for (final c in snap.data!) if (_q.isEmpty || c.name.toLowerCase().contains(_q)) c];
                if (rows.isEmpty) {
                  return Center(
                    child: Text(snap.data!.isEmpty
                        ? 'No Dispatchers, and no passengers with a seat this week.'
                        : 'Nobody by that name.',
                        textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                  );
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final c = rows[i];
                    final firstOfGroup = i == 0 || rows[i - 1].role != c.role;
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (firstOfGroup)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                          child: Text(c.role == 'dispatcher' ? 'DISPATCHERS' : 'PASSENGERS WITH A SEAT THIS WEEK',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  letterSpacing: .6, color: AppColors.textMuted)),
                        ),
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        hoverColor: AppColors.hoverWash,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(c.role == 'dispatcher' ? Icons.badge_outlined : Icons.person_outline,
                              size: 16, color: AppColors.primary),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: c.tripLabel == null ? null : Text(c.tripLabel!),
                        onTap: () => Navigator.pop(context, c),
                      ),
                    ]);
                  },
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MessagingProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text('Conversations', style: Theme.of(context).textTheme.titleSmall),
        ),
        const Divider(height: 1),
        Expanded(child: _body(p)),
      ],
    );
  }

  Widget _body(MessagingProvider p) {
    if (p.listError != null && p.conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load messages.\n${p.listError}',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    if (p.isLoadingList && p.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (p.conversations.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No conversations yet',
        hint: 'A conversation appears here when crew or a passenger sends a message.',
      );
    }
    return ListView.separated(
      itemCount: p.conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = p.conversations[i];
        final isOpen = c.conversationId == p.openConversationId;
        final unread = c.unreadCount > 0;
        return ListTile(
          selected: isOpen,
          selectedTileColor: AppColors.surfaceSunken,
          leading: CircleAvatar(child: Icon(_iconFor(c.peerRole), size: 18)),
          title: Text(c.peerName,
              style: TextStyle(fontSize: 13, fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
          subtitle: Text(
            c.lastMessage ?? 'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: unread ? AppColors.textPrimary : AppColors.textMuted),
          ),
          trailing: unread
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration:
                      BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('${c.unreadCount}',
                      style: TextStyle(fontSize: 11, color: AppColors.onFill)),
                )
              : null,
          onTap: () {
            p.openConversation(c.conversationId);
            // Opening the thread reads it; clear the sidebar badge now
            // rather than at the next poll.
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) context.read<ReviewCounts>().refresh();
            });
          },
        );
      },
    );
  }

  IconData _iconFor(String role) {
    switch (role) {
      case 'dispatcher':
        return Icons.badge_outlined;
      // Legacy threads only: drivers have no accounts since migration 017.
      case 'driver':
        return Icons.airline_seat_recline_normal;
      case 'passenger':
        return Icons.person_outline;
      default:
        return Icons.person_outline;
    }
  }
}

class _Thread extends StatelessWidget {
  const _Thread({required this.textController});

  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MessagingProvider>();
    if (p.openConversationId == null) {
      return Center(
        child: Text('Select a conversation.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final open = p.conversations.where((c) => c.conversationId == p.openConversationId).firstOrNull;
    return Column(
      children: [
        // Who the office is talking to (the reference's thread header).
        if (open != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.surfaceRaised,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryContainer,
                child: Text(open.peerName.isEmpty ? '?' : open.peerName.characters.first.toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(open.peerName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(_roleWord(open.peerRole), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
            ]),
          ),
        Expanded(child: Container(color: AppColors.surface, child: _messages(p))),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surfaceRaised,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: open == null ? 'Reply as the cooperative office' : 'Reply to ${open.peerName}…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: AppColors.divider)),
                  ),
                  onSubmitted: (_) => _send(p),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: p.isSending ? null : () => _send(p),
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _send(MessagingProvider p) async {
    final text = textController.text;
    if (text.trim().isEmpty) return;
    textController.clear();
    await p.send(text);
  }

  Widget _messages(MessagingProvider p) {
    if (p.threadError != null && p.messages.isEmpty) {
      return Center(
        child: Text('Could not load this conversation.\n${p.threadError}',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
      );
    }
    if (p.isLoadingThread && p.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (p.messages.isEmpty) {
      return Center(child: Text('No messages yet.', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: p.messages.length,
      itemBuilder: (context, i) => _bubble(context, p, p.messages[i]),
    );
  }

  static String _roleWord(String role) => switch (role) {
        'dispatcher' => 'Dispatcher',
        'passenger' => 'Passenger',
        'cashier' => 'Cashier',
        'terminal_manager' => 'Terminal Manager',
        _ => role,
      };

  Future<void> _editMessage(BuildContext context, MessagingProvider p, ConsoleMessage m) async {
    final text = await askText(
      context,
      title: 'Edit message',
      intro: 'The other person sees the new text, marked "edited".',
      label: 'Message',
      confirmLabel: 'Save',
      maxLength: 1000,
      initial: m.body,
    );
    if (text == null || text.trim().isEmpty || text.trim() == m.body) return;
    final err = await p.edit(m, text);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _deleteMessage(BuildContext context, MessagingProvider p, ConsoleMessage m) async {
    final ok = await askConfirm(
      context,
      title: 'Delete this message?',
      body: 'Its text is removed for both sides. The conversation shows '
          '"Message deleted" where it was.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    final err = await p.delete(m);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _bubble(BuildContext context, MessagingProvider p, ConsoleMessage m) {
    final align = m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // The office's own messages green, the other side's white with an
    // edge; the corner by the sender is squared off.
    final color = m.isMine ? AppColors.primary : AppColors.surfaceRaised;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              border: m.isMine ? null : Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(m.isMine ? 16 : 4),
                topRight: Radius.circular(m.isMine ? 4 : 16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
            ),
            child: m.deleted
                ? Text('Message deleted',
                    style: TextStyle(
                        color: m.isMine ? AppColors.onFill.withValues(alpha: .8) : AppColors.textMuted,
                        fontSize: 14,
                        fontStyle: FontStyle.italic))
                : Text(m.body, style: TextStyle(color: m.isMine ? AppColors.onFill : AppColors.textPrimary, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  DateFormat('MMM dd, hh:mm a').format(m.createdAt) +
                      (m.edited && !m.deleted ? ' · edited' : ''),
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              if (m.canChange) ...[
                const SizedBox(width: 6),
                _MiniAction(
                    icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editMessage(context, p, m)),
                _MiniAction(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    danger: true,
                    onTap: () => _deleteMessage(context, p, m)),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// The small Edit / Delete under one's own message: a word beside its icon
/// so it is clear what it does, with a hover wash so it reads as clickable.
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.hoverWash,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
