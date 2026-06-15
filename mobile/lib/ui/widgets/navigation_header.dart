import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class NavigationHeader extends StatelessWidget {
  final String distance;
  final String instruction;
  final String totalDistanceLeft;

  const NavigationHeader({
    Key? key,
    required this.distance,
    required this.instruction,
    required this.totalDistanceLeft,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24), // Extra top padding for status bar
      decoration: const BoxDecoration(
        color: Color(0xFF2E3440), // Dark slate/purple tint
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("In $distance", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text(instruction, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(totalDistanceLeft, style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("meters", style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          )
        ],
      ),
    );
  }
}