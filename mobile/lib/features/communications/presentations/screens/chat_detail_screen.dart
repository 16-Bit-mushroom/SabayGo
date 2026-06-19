import 'package:flutter/material.dart';

class ChatDetailScreen extends StatefulWidget {
  final String driverName;
  const ChatDetailScreen({Key? key, required this.driverName}) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isComposing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 16),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                const CircleAvatar(radius: 18, backgroundColor: Color(0xFFF3F0FF), child: Icon(Icons.person, color: Color(0xFF2D2059), size: 20)),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: const Color(0xFF00A859), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.driverName, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                const Text("Online · Driver", style: TextStyle(color: Color(0xFF00A859), fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: IconButton(icon: const Icon(Icons.call_outlined, color: Color(0xFF00A859), size: 20), onPressed: () {}),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: IconButton(icon: const Icon(Icons.more_vert, color: Colors.black, size: 20), onPressed: () {}),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                    child: const Text("Today", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
                _buildMessageBubble("Hello! I'm your driver Marcus. I'm on my way.", "9:05 AM", false),
                _buildMessageBubble("Great! I'm downstairs waiting.", "9:06 AM", true),
                _buildMessageBubble("Perfect, I can see you on the map. ETA 5 mins.", "9:07 AM", false),
                _buildMessageBubble("Okay, I'll stay at the main entrance 👍", "9:08 AM", true),
                _buildMessageBubble("I'm 2 minutes away, please be ready!", "9:12 AM", false),
              ],
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, String time, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const CircleAvatar(radius: 12, backgroundColor: Color(0xFFF3F0FF), child: Icon(Icons.person, color: Color(0xFF2D2059), size: 14)),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF5A4499) : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: isMe ? null : Border.all(color: Colors.grey.shade200),
                ),
                child: Text(text, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14)),
              ),
              const SizedBox(height: 4),
              Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      bottom: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (text) {
                  setState(() {
                    _isComposing = text.trim().isNotEmpty;
                  });
                },
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide(color: Color(0xFF5A4499))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // INJECTED: GestureDetector instead of IconButton for absolute color control
            GestureDetector(
              onTap: _isComposing 
                ? () {
                    _controller.clear();
                    setState(() {
                      _isComposing = false; 
                    });
                    // Handle send logic here
                  }
                : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isComposing ? const Color(0xFF5A4499) : Colors.white, 
                  shape: BoxShape.circle, 
                  border: Border.all(color: _isComposing ? const Color(0xFF5A4499) : Colors.grey.shade300)
                ),
                child: Icon(
                  Icons.send, 
                  color: _isComposing ? Colors.white : const Color(0xFFD0C9E8), 
                  size: 20,
                ),
              ),
            ),
            
          ],
        ),
      ),
    );
  }
}