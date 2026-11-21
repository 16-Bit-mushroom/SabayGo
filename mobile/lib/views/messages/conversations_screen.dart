import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/empty_state.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../models/message_model.dart';
import '../../viewmodels/conversations_viewmodel.dart';
import 'conversation_thread_screen.dart';
import 'new_conversation_screen.dart';

class ConversationsScreen extends StatefulWidget {
  /// Pass a [viewModel] to share one already polling elsewhere (an app-bar
  /// badge); omit it and the screen owns its own, same shape as
  /// NotificationsScreen.
  const ConversationsScreen({super.key, this.viewModel});

  final ConversationsViewModel? viewModel;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ConversationsViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ??
        ConversationsViewModel(MessagingRepository(context.read<ApiClient>()));
    _viewModel.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _openThread(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationThreadScreen(
          conversationId: c.id,
          peerName: c.peerName,
          peerRole: c.peerRole,
        ),
      ),
    );
    _viewModel.load();
  }

  Future<void> _startNew() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewConversationScreen()),
    );
    _viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _viewModel.load, child: _body()),
      ),
      // Labelled, not a bare pencil (20 Nov redesign).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNew,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New message'),
      ),
    );
  }

  Widget _body() {
    final conversations = _viewModel.conversations;
    if (_viewModel.isLoading && conversations.isEmpty && _viewModel.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null && conversations.isEmpty) {
      return const AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load messages',
        body: 'Check your connection, then pull down to try again.',
      );
    }
    if (conversations.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No messages yet',
        body: 'Tap New message to write to your trip\'s Dispatcher or the A2Z office.',
      );
    }
    // Cards with a gap (20 Nov redesign), and room at the foot for the
    // floating button.
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 96),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _tile(conversations[i]),
    );
  }

  Widget _tile(Conversation c) {
    final unread = c.unreadCount > 0;
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: unread ? AppColors.primaryLight : AppColors.edge, width: unread ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: () => _openThread(c),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryContainer,
              child: Icon(_iconFor(c.peerRole), color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(c.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge!.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  if (c.lastMessageAt != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(_formatTimestamp(c.lastMessageAt!), style: text.bodySmall),
                  ],
                ]),
                Text(_roleLabel(c.peerRole),
                    style: text.labelMedium!.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(
                      c.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium!.copyWith(color: unread ? AppColors.textPrimary : AppColors.textMuted),
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.full)),
                      child: Text('${c.unreadCount}',
                          semanticsLabel: '${c.unreadCount} unread',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onFill)),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _roleLabel(String role) => switch (role) {
        'terminal_manager' || 'cashier' => 'A2Z office',
        'dispatcher' => 'Dispatcher',
        // Legacy threads only: drivers have no accounts since migration 017.
        'driver' => 'Driver',
        _ => 'Passenger',
      };

  IconData _iconFor(String role) {
    switch (role) {
      case 'terminal_manager':
      case 'cashier':
        return Icons.storefront;
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

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24 && now.day == dt.day) return DateFormat('hh:mm a').format(dt);
    if (difference.inDays < 7) return DateFormat('EEE').format(dt);
    return DateFormat('MMM dd').format(dt);
  }
}
