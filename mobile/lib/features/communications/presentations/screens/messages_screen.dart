import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/viewmodels/booking_viewmodel.dart';
import 'package:mobile/features/booking/viewmodels/driver_viewmodel.dart';
import 'package:provider/provider.dart';
import 'chat_detail_screen.dart'; 

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Check Passenger State
    final bookingVM = context.watch<BookingViewModel>();
    final activeMatch = bookingVM.currentMatch;
    final isPassengerActive = activeMatch != null && 
        (bookingVM.currentStep == BookingStep.matched || bookingVM.currentStep == BookingStep.inRide);

    // 2. Check Driver State
    final driverVM = context.watch<DriverViewModel>();
    final isDriverActive = driverVM.currentStep == DriverStep.headingToPickup || 
                           driverVM.currentStep == DriverStep.arrivedAtPickup || 
                           driverVM.currentStep == DriverStep.inRide;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text("Messages", style: TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: Icon(Icons.more_horiz, color: Colors.grey.shade400), onPressed: () {}),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search conversations...",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              ),
            ),
          ),
          
          // Conversation List
          Expanded(
            child: ListView(
              children: [
                // DYNAMIC PINNED CHAT FOR PASSENGERS
                if (isPassengerActive) ...[
                  Container(
                    color: AppColors.primaryAction.withOpacity(0.05),
                    child: _buildChatTile(
                      context,
                      name: activeMatch.driverName,
                      message: "Tap to message your current driver.",
                      time: "Now",
                      unreadCount: 0,
                      role: "Active Driver",
                      roleColor: AppColors.primaryAction.withOpacity(0.2),
                      roleTextColor: AppColors.primaryAction,
                      isOnline: true,
                      isPinned: true,
                    ),
                  ),
                  const Divider(height: 1, indent: 72),
                ],

                // DYNAMIC PINNED CHAT FOR DRIVERS
                if (isDriverActive) ...[
                  Container(
                    color: AppColors.success.withOpacity(0.05),
                    child: _buildChatTile(
                      context,
                      name: "Sarah K.", // Mocked active passenger
                      message: "Tap to message your current passenger.",
                      time: "Now",
                      unreadCount: 0,
                      role: "Active Passenger",
                      roleColor: AppColors.success.withOpacity(0.2),
                      roleTextColor: AppColors.success,
                      isOnline: true,
                      isPinned: true,
                    ),
                  ),
                  const Divider(height: 1, indent: 72),
                ],

                // Static Mock Chats Below
                _buildChatTile(
                  context,
                  name: "Marcus D.",
                  message: "Thanks for the ride! 🌿",
                  time: "Yesterday",
                  unreadCount: 0,
                  role: "Past Trip",
                  roleColor: Colors.transparent,
                  roleTextColor: Colors.grey,
                  isOnline: false,
                ),
                const Divider(height: 1, indent: 72),
                _buildChatTile(
                  context,
                  name: "SabayGo Support",
                  message: "Your profile verification is complete.",
                  time: "Mon",
                  unreadCount: 1,
                  role: "Support",
                  roleColor: const Color(0xFFE5F6EE),
                  roleTextColor: const Color(0xFF00A859),
                  isOnline: true,
                  isSupport: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(BuildContext context, {
    required String name, required String message, required String time,
    required int unreadCount, required String role, required Color roleColor,
    required Color roleTextColor, required bool isOnline, bool isSupport = false, bool isPinned = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              receiverName: name,
              role: role.contains("Driver") ? "Driver" : (role.contains("Support") ? "Support" : "Passenger"),
            )
          ),
        );
      },
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isSupport ? const Color(0xFF2D2059) : const Color(0xFFF3F0FF),
            child: Icon(isSupport ? Icons.security : Icons.person, color: isSupport ? Colors.white : const Color(0xFF2D2059)),
          ),
          if (isOnline)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: const Color(0xFF00A859), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              ),
            ),
        ],
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (isPinned) ...[
                const SizedBox(width: 4),
                const Icon(Icons.push_pin, size: 14, color: AppColors.primaryAction),
              ]
            ],
          ),
          Text(time, style: TextStyle(color: unreadCount > 0 ? const Color(0xFF2D2059) : Colors.grey, fontSize: 12, fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unreadCount > 0 ? Colors.black87 : Colors.grey, fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal)),
          const SizedBox(height: 6),
          if (roleColor != Colors.transparent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(4)),
              child: Text(role, style: TextStyle(color: roleTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          else
            Text(role, style: TextStyle(color: roleTextColor, fontSize: 10)),
        ],
      ),
      trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Color(0xFF2D2059), shape: BoxShape.circle),
              child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}