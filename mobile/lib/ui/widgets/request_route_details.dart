import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class RequestRouteDetails extends StatelessWidget {
  final String passengerName;
  final String passengerRating;
  final String pickupNode;
  final String dropoffNode;
  final String totalDistance;
  final String estTime;

  const RequestRouteDetails({
    Key? key,
    required this.passengerName,
    required this.passengerRating,
    required this.pickupNode,
    required this.dropoffNode,
    required this.totalDistance,
    required this.estTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // INJECTED: Passenger Trust Info
          Row(
            children: [
              const CircleAvatar(radius: 14, backgroundColor: Colors.deepPurple, child: Icon(Icons.person, size: 16, color: Colors.white)),
              const SizedBox(width: 8),
              Text(passengerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              const Icon(Icons.star, color: Colors.amber, size: 14),
              const SizedBox(width: 4),
              Text(passengerRating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          
          // Route Info
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.orange),
                  Container(height: 20, width: 2, color: Colors.grey.shade300),
                  const Icon(Icons.circle, size: 10, color: AppColors.success),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$pickupNode — Pickup", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 16),
                    Text("$dropoffNode — Drop-off", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(totalDistance, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(estTime, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }
}