import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    if (_viewModel.messages.isEmpty) {
      return Center(
        child: Text('Say hello to ${widget.peerName}.', style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _viewModel.messages.length,
      itemBuilder: (context, i) => _bubble(_viewModel.messages[i]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final align = m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = m.isMine ? AppColors.success : Colors.grey.shade200;
    final textColor = m.isMine ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(m.body, style: TextStyle(color: textColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              DateFormat('hh:mm a').format(m.createdAt),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
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
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _viewModel.isSending ? null : _send,
              style: IconButton.styleFrom(backgroundColor: AppColors.success),
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'coop_admin':
        return 'Cooperative office';
      case 'conductor':
        return 'Conductor';
      case 'driver':
        return 'Driver';
      case 'passenger':
        return 'Passenger';
      default:
        return role;
    }
  }
}
