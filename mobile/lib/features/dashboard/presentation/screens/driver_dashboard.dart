import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/viewmodels/driver_viewmodel.dart';
import 'package:mobile/features/communications/presentations/screens/chat_detail_screen.dart';
import 'package:mobile/features/communications/presentations/screens/messages_screen.dart';
import 'package:mobile/features/identity/presentation/screens/edit_profile_screen.dart';
import 'package:mobile/features/identity/presentation/screens/login_screen.dart';
import 'package:mobile/features/identity/presentation/screens/profile_screen.dart';
import 'package:mobile/features/identity/viewmodels/profile_viewmodel.dart';
import 'package:mobile/features/trip/presentation/screens/driver_navigation_screen.dart';
import 'package:mobile/features/trip/presentation/screens/driver_trip_summary_screen.dart';
import 'package:mobile/features/trip/presentation/screens/ride_request_screen.dart';
import 'package:provider/provider.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  int _currentIndex = 0;

  // Triggers when Message or Call is tapped
  void _showPassengerSelection(BuildContext context, String actionType) {
    
    // Internal helper function to handle the selection routing
    void handleAction(String passengerName) {
      Navigator.pop(context); // Close the bottom sheet first
      
      if (actionType == "Message") {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              receiverName: passengerName,
              role: "Passenger", // Dynamically sets the role
            ),
          ),
        );
      } else if (actionType == "Call") {
        // Trigger the identical VoIP dialog for the driver
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
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
                  "Calling ${passengerName.split(' ').first}...",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text("Secure VoIP connection", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  elevation: 0,
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Icon(Icons.call_end, color: Colors.white),
                )
              ],
            ),
          ),
        );
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Select Passenger to $actionType",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.person), 
                title: const Text("Sarah K."), 
                onTap: () => handleAction("Sarah K.") // FIXED: Now routes properly
              ),
              ListTile(
                leading: const Icon(Icons.person), 
                title: const Text("Mark D."), 
                onTap: () => handleAction("Mark D.") // FIXED: Now routes properly
              ),
              ListTile(
                leading: const Icon(Icons.person), 
                title: const Text("Chloe S."), 
                onTap: () => handleAction("Chloe S.") // FIXED: Now routes properly
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Triggers when Start Ride is tapped
  void _showBoardingConfirmation(BuildContext context, DriverViewModel viewModel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Boarding"),
        content: const Text("Has Sarah K. successfully boarded the vehicle?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.resetToOnline(); // Driver cancels
            },
            child: const Text("No, Cancel Ride", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.startRide(); // Triggers the In-Ride Map transition
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text("Yes, Start Ride", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Triggers when Complete Trip is tapped
  void _showPaymentConfirmation(BuildContext context, DriverViewModel viewModel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Receive Contribution"),
        // CHANGED: Language updated to reflect cost-sharing, not earning
        content: const Text("Confirm receipt of ₱53.20 (Cash) from Sarah K. for their share of the fuel cost."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.completeRide();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text("Confirm Receipt", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DriverViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildBody(context, viewModel),

      // Driver-specific Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primaryAction,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"), // ADDED BACK
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
Widget _buildBody(BuildContext context, DriverViewModel viewModel) {
    if (_currentIndex == 1) return const Center(child: Text("Trip History & Shared Costs"));
    if (_currentIndex == 2) return const MessagesScreen(); // WIRED UP
    
    if (_currentIndex == 3) {
      return ProfileScreen(
        onEditProfile: () {
          final currentUser = context.read<ProfileViewModel>().currentUser;
          
          // Split the existing full name into First and Last
          final nameParts = (currentUser?.fullName ?? "").split(" ");
          final firstName = nameParts.isNotEmpty ? nameParts.first : "";
          final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(" ") : "";

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditProfileScreen(
                currentUserData: {
                  'firstName': firstName,
                  'lastName': lastName,
                  'email': 'driver@example.edu.ph', 
                  'phoneNumber': '+639171234567',
                  'emergencyContactName': 'Maria Dela Cruz',
                  'emergencyContactPhone': '+639189876543',
                },
              ),
            ),
          );
        },
        onSettingsTap: (setting) => debugPrint("$setting Tapped"),
        onSignOut: () {
          // Reset the driver state before logging out
          viewModel.resetToOnline(); 
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        },
      );
    }

    // Home Tab (Index 0) Controls the Driver Shift Lifecycle
    switch (viewModel.currentStep) {
      
      // BOTH Offline and Online use the new interactive Map HUD
      case DriverStep.offline:
        return _buildMapHomeState(context, viewModel, isOnline: false);
      case DriverStep.online:
        return _buildMapHomeState(context, viewModel, isOnline: true);

      case DriverStep.requestReceived:
        return RideRequestScreen(
          onAccept: () => viewModel.acceptRequest(),
          onDecline: () => viewModel.declineRequest(),
        );

      case DriverStep.headingToPickup:
        return DriverNavigationScreen(
          currentStep: viewModel.currentStep,
          onMainAction: () => viewModel.arriveAtPickup(),
          onMessage: () => _showPassengerSelection(context, "Message"),
          onCall: () => _showPassengerSelection(context, "Call"),
        );

      case DriverStep.arrivedAtPickup:
        return DriverNavigationScreen(
          currentStep: viewModel.currentStep,
          onMainAction: () => _showBoardingConfirmation(context, viewModel),
          onMessage: () => _showPassengerSelection(context, "Message"),
          onCall: () => _showPassengerSelection(context, "Call"),
        );

      case DriverStep.inRide:
        return DriverNavigationScreen(
          currentStep: viewModel.currentStep,
          onMainAction: () => _showPaymentConfirmation(context, viewModel),
          onMessage: () => _showPassengerSelection(context, "Message"),
          onCall: () => _showPassengerSelection(context, "Call"),
        );

      case DriverStep.completed:
        return DriverTripSummaryScreen(
          onFindNextRide: () => viewModel.resetToOnline(), 
          onGoOffline: () {
            viewModel.resetToOnline(); 
            viewModel.toggleStatus();  
          },
        );

      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  // --- THE NEW MAP HUD ---
  Widget _buildMapHomeState(BuildContext context, DriverViewModel viewModel, {required bool isOnline}) {
    return Stack(
      children: [
        // 1. BACKGROUND MAP
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            color: isOnline ? AppColors.highlight.withOpacity(0.3) : Colors.grey.shade200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isOnline ? Icons.radar : Icons.location_off,
                    size: 64,
                    color: isOnline ? AppColors.primaryAction.withOpacity(0.5) : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isOnline ? "Searching for carpoolers..." : "You are offline",
                    style: TextStyle(
                      color: isOnline ? AppColors.primaryAction : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  )
                ],
              ),
            ),
          ),
        ),

        // 2. TOP HUD: Eco-Impact & Menu
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Button
                FloatingActionButton.small(
                  heroTag: "driver_menu",
                  onPressed: () {},
                  backgroundColor: AppColors.surface,
                  elevation: 2,
                  child: const Icon(Icons.person, color: AppColors.textPrimary),
                ),

                // CHANGED: Eco-Impact Pill instead of Earnings
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text("CO₂ Saved Today", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text("4.2 kg", style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

                // Secret Debug Button to trigger a ride request
                FloatingActionButton.small(
                  heroTag: "debug_ping",
                  onPressed: () {
                    if (!isOnline) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must be Online to receive requests.")));
                      return;
                    }
                    viewModel.simulateIncomingRequest();
                  },
                  backgroundColor: Colors.amber,
                  elevation: 2,
                  child: const Icon(Icons.notification_add, color: AppColors.surface),
                ),
              ],
            ),
          ),
        ),

        // 3. BOTTOM HUD: The Master Toggle
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.transparent),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatMetric(Icons.star, "4.9", "Rating"),
                      _buildStatMetric(Icons.local_gas_station, "12L", "Fuel Shared"), // Changed to Fuel Shared
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // The Big GO ONLINE Button
                  GestureDetector(
                    onTap: () {
                      viewModel.toggleStatus();
                      if (!isOnline) { // It was offline, now turning online
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("You are now online. Searching for carpoolers..."),
                            backgroundColor: AppColors.success,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.red.shade600 : AppColors.success,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline ? Colors.red : AppColors.success).withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isOnline ? "GO OFFLINE" : "GO ONLINE",
                          style: const TextStyle(color: AppColors.surface, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatMetric(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primaryAction),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          )
        ],
      ),
    );
  }
}