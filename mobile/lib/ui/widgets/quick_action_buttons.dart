import 'package:flutter/material.dart';

class QuickActionButtons extends StatelessWidget {
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final VoidCallback onCancel;

  const QuickActionButtons({
    Key? key,
    required this.onMessage,
    required this.onCall,
    required this.onCancel,
  }) : super(key: key);

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildActionButton("Message", Icons.chat_bubble_outline, Colors.deepPurple, onMessage),
        const SizedBox(width: 12),
        _buildActionButton("Call", Icons.phone_outlined, Colors.green, onCall),
        const SizedBox(width: 12),
        _buildActionButton("Cancel", Icons.close, Colors.red, onCancel),
      ],
    );
  }
}