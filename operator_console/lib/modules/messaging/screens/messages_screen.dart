import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../data/repositories/messaging_repository.dart';
import '../../../viewmodels/messaging_provider.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';

/// The cooperative office's shared inbox: every passenger, conductor and
/// driver thread with coop_admin lands here, and any signed-in office
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
                  'cooperative office.',
              actions: [RefreshButton(onPressed: _provider.refreshConversations)],
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
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
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
                      style: const TextStyle(fontSize: 11, color: AppColors.onFill)),
                )
              : null,
          onTap: () => p.openConversation(c.conversationId),
        );
      },
    );
  }

  IconData _iconFor(String role) {
    switch (role) {
      case 'conductor':
        return Icons.badge_outlined;
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
      return const Center(
        child: Text('Select a conversation.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      children: [
        Expanded(child: _messages(p)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Reply as the cooperative office',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(p),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: p.isSending ? null : () => _send(p),
                child: const Text('Send'),
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
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      );
    }
    if (p.isLoadingThread && p.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (p.messages.isEmpty) {
      return const Center(child: Text('No messages yet.', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: p.messages.length,
      itemBuilder: (context, i) => _bubble(p.messages[i]),
    );
  }

  Widget _bubble(ConsoleMessage m) {
    final align = m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = m.isMine ? AppColors.info : AppColors.surfaceSunken;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Text(m.body, style: TextStyle(color: m.isMine ? AppColors.onFill : AppColors.textPrimary, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(DateFormat('MMM dd, hh:mm a').format(m.createdAt),
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}
