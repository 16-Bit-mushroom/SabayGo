import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/dialog_buttons.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../models/message_model.dart';
import '../../viewmodels/conversation_thread_viewmodel.dart';

class ConversationThreadScreen extends StatefulWidget {
  const ConversationThreadScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
    required this.peerRole,
  });

  final String conversationId;
  final String peerName;
  final String peerRole;

  @override
  State<ConversationThreadScreen> createState() => _ConversationThreadScreenState();
}

class _ConversationThreadScreenState extends State<ConversationThreadScreen> {
  late final ConversationThreadViewModel _viewModel;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _viewModel = ConversationThreadViewModel(
      MessagingRepository(context.read<ApiClient>()),
      widget.conversationId,
    );
    _viewModel.addListener(_onChanged);
  }

  void _onChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    await _viewModel.send(text);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 16)),
            Text(
              _roleLabel(widget.peerRole),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_viewModel.isLoading && _viewModel.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null && _viewModel.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load this conversation.\n${_viewModel.error}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    if (_viewModel.messages.isEmpty) {
      return Center(
        child: Text('No messages yet. Write to ${widget.peerName} below.', style: const TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _viewModel.messages.length,
      itemBuilder: (context, i) => _bubble(_viewModel.messages[i]),
    );
  }

  /// Mine on the soft green, theirs on white, both edged (20 Nov redesign):
  /// quieter than the solid green bubble it replaces, and the text stays
  /// the ink colour on both. One's own message opens Edit and Delete on a
  /// tap or a long press.
  Widget _bubble(ChatMessage m) {
    final align = m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final fill = m.isMine ? AppColors.primaryContainer : AppColors.surfaceRaised;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: m.isMine ? AppColors.primaryLight.withValues(alpha: 0.5) : AppColors.edge),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: m.canChange ? () => _actions(m) : null,
              onLongPress: m.canChange ? () => _actions(m) : null,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: m.deleted
                    ? const Text('Message deleted',
                        style: TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic))
                    : Text(m.body, style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              DateFormat('h:mm a').format(m.createdAt) +
                  (m.edited && !m.deleted ? ' · edited' : '') +
                  (m.canChange ? ' · tap to edit' : ''),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// A tap or long press on one's own message: Edit or Delete.
  Future<void> _actions(ChatMessage m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit message'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text('Delete message', style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    String? err;
    if (choice == 'edit') {
      final text = await _askEdit(m.body);
      if (text == null || text.trim().isEmpty || text.trim() == m.body) return;
      err = await _viewModel.edit(m, text);
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this message?'),
          content: const Text('Its text is removed for both of you. "Message deleted" stays where it was.'),
          actions: [
            DialogButtons(
              action: 'Delete',
              danger: true,
              onAction: () => Navigator.pop(ctx, true),
              onCancel: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      );
      if (ok != true) return;
      err = await _viewModel.delete(m);
    }
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<String?> _askEdit(String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          DialogButtons(action: 'Save', onAction: () => Navigator.pop(ctx, c.text)),
        ],
      ),
    ); // c is not disposed here: the dialog still reads it while it animates out.
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                // The theme's outlined field: a box the eye can find (3:1 edge).
                decoration: const InputDecoration(hintText: 'Message'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            // A labelled button, not an icon alone (20 Nov redesign).
            FilledButton.icon(
              onPressed: _viewModel.isSending ? null : _send,
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'terminal_manager':
      case 'cashier':
        return 'A2Z office';
      case 'dispatcher':
        return 'Dispatcher';
      // Legacy threads only: drivers have no accounts since migration 017.
      case 'driver':
        return 'Driver';
      case 'passenger':
        return 'Passenger';
      default:
        return role;
    }
  }
}
