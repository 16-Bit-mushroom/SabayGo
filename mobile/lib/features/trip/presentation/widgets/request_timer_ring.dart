import 'package:flutter/material.dart';

class RequestTimerRing extends StatelessWidget {
  final int secondsLeft;
  final double progress; // 0.0 to 1.0

  const RequestTimerRing({
    Key? key,
    required this.secondsLeft,
    required this.progress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              secondsLeft <= 3 ? Colors.red : Colors.amber,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  secondsLeft.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.0),
                ),
                const Text(
                  "sec",
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}