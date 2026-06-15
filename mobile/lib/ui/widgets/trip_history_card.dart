import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TripHistoryCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final int currentRating; // 0 means unrated
  final bool isRatingSaved;
  final Function(int) onRate;
  final VoidCallback onSaveRating;
  final VoidCallback onEditRating;

  // Dummy data properties (in a real app, pass a DTO here)
  final String origin;
  final String destination;
  final String price;
  final bool isEco;
  final bool isCompleted;

  const TripHistoryCard({
    Key? key,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.currentRating,
    required this.isRatingSaved,
    required this.onRate,
    required this.onSaveRating,
    required this.onEditRating,
    required this.origin,
    required this.destination,
    required this.price,
    this.isEco = true,
    this.isCompleted = true,
  }) : super(key: key);

  Widget _buildPill(String label, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 10, color: color), const SizedBox(width: 2)],
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildExpandedStat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Collapsed View (Always visible)
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(backgroundColor: AppColors.primaryAction.withOpacity(0.1), child: const Icon(Icons.person, color: AppColors.primaryAction)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [const Icon(Icons.circle, size: 8, color: Colors.deepPurple), const SizedBox(width: 8), Text(origin, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
                        const SizedBox(height: 4),
                        Row(children: [const Icon(Icons.location_on, size: 10, color: AppColors.highlight), const SizedBox(width: 6), Text(destination, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text("Jun 11, 2026 · 9:14 AM", style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                            const SizedBox(width: 8),
                            if (isEco) _buildPill("Eco", AppColors.success, Icons.eco),
                            const SizedBox(width: 4),
                            _buildPill(isCompleted ? "Done" : "Cancelled", isCompleted ? AppColors.success : Colors.red, isCompleted ? Icons.check : Icons.close),
                          ],
                        )
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(price, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isCompleted ? AppColors.textPrimary : AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
                    ],
                  )
                ],
              ),
            ),
          ),
          
          // Expanded View
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Row
                  Row(
                    children: [
                      _buildExpandedStat("5.2 km", "Distance"),
                      const SizedBox(width: 8),
                      _buildExpandedStat("22 min", "Duration"),
                      const SizedBox(width: 8),
                      _buildExpandedStat("Shared", "Type"),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Driver Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(radius: 12, backgroundColor: Colors.grey, child: Icon(Icons.person, size: 12, color: Colors.white)),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Marcus W.", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Row(children: const [Icon(Icons.star, size: 10, color: Colors.amber), Icon(Icons.star, size: 10, color: Colors.amber), Icon(Icons.star, size: 10, color: Colors.amber), Icon(Icons.star, size: 10, color: Colors.amber), Icon(Icons.star, size: 10, color: Colors.amber), SizedBox(width: 4), Text("4.9", style: TextStyle(fontSize: 10, color: AppColors.textSecondary))]),
                            ],
                          )
                        ],
                      ),
                      const Text("Saved ₱30", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Rating Section
                  const Text("RATE YOUR DRIVER", style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: isRatingSaved ? null : () => onRate(index + 1),
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: currentRating > index ? Colors.deepPurple.withOpacity(0.1) : AppColors.surface,
                                border: Border.all(color: currentRating > index ? Colors.deepPurple : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                currentRating > index ? Icons.star : Icons.star_border,
                                size: 16,
                                color: currentRating > index ? Colors.amber : AppColors.textSecondary,
                              ),
                            ),
                          );
                        }),
                      ),
                      // Dynamic Save/Edit Button
                      TextButton(
                        onPressed: isRatingSaved ? onEditRating : (currentRating > 0 ? onSaveRating : null),
                        style: TextButton.styleFrom(
                          foregroundColor: isRatingSaved ? AppColors.textSecondary : AppColors.primaryAction,
                        ),
                        child: Text(isRatingSaved ? "Edit" : "Save", style: const TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  if (isRatingSaved)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text("Thanks for rating! ✓", style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            )
          ]
        ],
      ),
    );
  }
}