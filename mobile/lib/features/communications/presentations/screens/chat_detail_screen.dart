import 'package:flutter/material.dart';

// 1. The Data Model
class ChatMessage {
  final String id;
  String text;
  final bool isMe;
  final String time;
  String status;

  ChatMessage({required this.id, required this.text, required this.isMe, required this.time, this.status = 'sent'});
}

class ChatDetailScreen extends StatefulWidget {
  // CHANGED: Made generic so both Drivers and Passengers can use it
  final String receiverName;
  final String role; 

  const ChatDetailScreen({
    Key? key, 
    required this.receiverName, 
    required this.role
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isComposing = false;
  String? _editingMessageId;

  final List<ChatMessage> _messages = [
    ChatMessage(id: '1', text: "Hello! I'm on my way.", isMe: false, time: "9:05 AM"),
    ChatMessage(id: '2', text: "Great! I'm downstairs waiting.", isMe: true, time: "9:06 AM", status: 'read'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    if (_controller.text.trim().isEmpty) return;

    setState(() {
      if (_editingMessageId != null) {
        final msgIndex = _messages.indexWhere((m) => m.id == _editingMessageId);
        if (msgIndex != -1) _messages[msgIndex].text = _controller.text.trim();
        _editingMessageId = null;
      } else {
        _messages.add(ChatMessage(
          id: DateTime.now().toString(),
          text: _controller.text.trim(),
          isMe: true,
          time: "Just now",
          status: 'sent',
        ));
      }
      _controller.clear();
      _isComposing = false;
    });
  }

  void _showMessageOptions(ChatMessage message) {
    if (!message.isMe) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.status == 'failed')
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: const Text("Resend Message"),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => message.status = 'sent');
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.black87),
              title: const Text("Edit"),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _editingMessageId = message.id;
                  _controller.text = message.text;
                  _isComposing = true;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Unsend", style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (BuildContext dialogContext) {
                    return AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text("Unsend Message?", style: TextStyle(fontWeight: FontWeight.bold)),
                      content: const Text("This message will be removed for everyone in the chat. Are you sure?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            setState(() => _messages.removeWhere((m) => m.id == message.id));
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, elevation: 0),
                          child: const Text("Unsend", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFFE5F6EE),
              child: Icon(Icons.person, size: 40, color: Color(0xFF00A859)),
            ),
            const SizedBox(height: 16),
            Text(
              "Calling ${widget.receiverName.split(' ').first}...", // UPDATED TO USE GENERIC NAME
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text("Secure VoIP connection", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            FloatingActionButton(
              backgroundColor: Colors.red,
              elevation: 0,
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.call_end, color: Colors.white),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 16), onPressed: () => Navigator.pop(context)),
          ),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                const CircleAvatar(radius: 18, backgroundColor: Color(0xFFF3F0FF), child: Icon(Icons.person, color: Color(0xFF2D2059), size: 20)),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF00A859), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.receiverName, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), // UPDATED
                Text("Online · ${widget.role}", style: const TextStyle(color: Color(0xFF00A859), fontSize: 12)), // UPDATED
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: IconButton(icon: const Icon(Icons.call_outlined, color: Color(0xFF00A859), size: 20), onPressed: _showCallDialog),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    return GestureDetector(
      onLongPress: () => _showMessageOptions(msg),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Row(
          mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!msg.isMe) ...[
              const CircleAvatar(radius: 12, backgroundColor: Color(0xFFF3F0FF), child: Icon(Icons.person, color: Color(0xFF2D2059), size: 14)),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: msg.isMe ? const Color(0xFF5A4499) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                      bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                    ),
                    border: msg.isMe ? null : Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(msg.text, style: TextStyle(color: msg.isMe ? Colors.white : Colors.black87, fontSize: 14)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(msg.time, style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
                    if (msg.isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.status == 'read' ? Icons.done_all : (msg.status == 'failed' ? Icons.error_outline : Icons.check),
                        size: 12,
                        color: msg.status == 'read' ? Colors.blue : (msg.status == 'failed' ? Colors.red : Colors.grey.shade400),
                      ),
                    ]
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      bottom: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (text) => setState(() => _isComposing = text.trim().isNotEmpty),
                decoration: InputDecoration(
                  hintText: _editingMessageId != null ? "Edit message..." : "Type a message...",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide(color: Color(0xFF5A4499))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _isComposing ? _handleSend : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isComposing ? const Color(0xFF5A4499) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _isComposing ? const Color(0xFF5A4499) : Colors.grey.shade300),
                ),
                child: Icon(_editingMessageId != null ? Icons.check : Icons.send, color: _isComposing ? Colors.white : const Color(0xFFD0C9E8), size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}