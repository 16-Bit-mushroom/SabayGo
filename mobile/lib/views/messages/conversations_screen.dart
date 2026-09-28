import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
      floatingActionButton: FloatingActionButton(
        onPressed: _startNew,
        tooltip: 'New message',
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _body() {
    final conversations = _viewModel.conversations;
    if (_viewModel.isLoading && conversations.isEmpty && _viewModel.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null && conversations.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Could not load messages.\nPull down to try again.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
        ],
      );
    }
    if (conversations.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: 320,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No messages yet', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text('Tap the pencil to start one', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _tile(conversations[i]),
    );
  }

  Widget _tile(Conversation c) {
    final unread = c.unreadCount > 0;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey.shade200,
        child: Icon(_iconFor(c.peerRole), color: Colors.grey.shade700),
      ),
      title: Text(c.peerName, style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500)),
      subtitle: Text(
        c.lastMessage ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: unread ? Colors.black87 : Colors.grey.shade600),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastMessageAt != null)
            Text(_formatTimestamp(c.lastMessageAt!), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          if (unread)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)),
              child: Text('${c.unreadCount}', style: const TextStyle(fontSize: 11, color: Colors.white)),
            ),
        ],
      ),
      onTap: () => _openThread(c),
    );
  }

  IconData _iconFor(String role) {
    switch (role) {
      case 'coop_admin':
        return Icons.storefront;
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

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24 && now.day == dt.day) return DateFormat('hh:mm a').format(dt);
    if (difference.inDays < 7) return DateFormat('EEE').format(dt);
    return DateFormat('MMM dd').format(dt);
  }
}
