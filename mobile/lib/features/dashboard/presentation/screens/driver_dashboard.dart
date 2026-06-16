import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/viewmodels/driver_viewmodel.dart';
import 'package:mobile/features/trip/presentation/screens/driver_navigation_screen.dart';
import 'package:mobile/features/trip/presentation/screens/driver_trip_summary_screen.dart';
import 'package:mobile/features/trip/presentation/screens/ride_request_screen.dart';
import 'package:provider/provider.dart';

// We will import your specific driver screens here as we build/refine them!
// import '../../trip/presentation/screens/ride_request_screen.dart';
// import '../../trip/presentation/screens/driver_navigation_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  int _currentIndex = 0;

  // Triggers when Message or Call is tapped
  void _showPassengerSelection(BuildContext context, String actionType) {
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("Sarah K."),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("Mark D."),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("Chloe S."),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Triggers when Start Ride is tapped
  void _showBoardingConfirmation(
    BuildContext context,
    DriverViewModel viewModel,
  ) {
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
            child: const Text(
              "No, Cancel Ride",
              style: TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.startRide(); // Triggers the In-Ride Map transition!
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text(
              "Yes, Start Ride",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Triggers when Complete Trip is tapped
  void _showPaymentConfirmation(
    BuildContext context,
    DriverViewModel viewModel,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Process Payment"),
        content: const Text(
          "Confirm collection of ₱53.20 (Cash) from Sarah K. to conclude this segment of the shared trip.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.completeRide();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text(
              "Confirm Payment",
              style: TextStyle(color: Colors.white),
            ),
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
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: "Earnings",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.star), label: "Ratings"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, DriverViewModel viewModel) {
    if (_currentIndex == 1)
      return const Center(child: Text("Earnings Dashboard"));
    if (_currentIndex == 2)
      return const Center(child: Text("Driver Ratings & Reviews"));
    if (_currentIndex == 3)
      return const Center(child: Text("Driver Profile & Settings"));

    // Home Tab (Index 0) Controls the Driver Shift Lifecycle
    switch (viewModel.currentStep) {
      case DriverStep.offline:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.power_settings_new,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                "You are currently offline.",
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => viewModel.toggleStatus(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAction,
                ),
                child: const Text(
                  "GO ONLINE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

      case DriverStep.online:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radar, size: 80, color: AppColors.primaryAction),
              const SizedBox(height: 16),
              const Text(
                "Searching for nearby requests...",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => viewModel
                    .simulateIncomingRequest(), // Secret trigger for your panel!
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                child: const Text(
                  "Simulate Incoming Request",
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => viewModel.toggleStatus(),
                child: const Text(
                  "Go Offline",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );

      case DriverStep.requestReceived:
        return RideRequestScreen(
          // We connect your UI buttons directly to the ViewModel's state machine
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
          onFindNextRide: () => viewModel.resetToOnline(), // Drops them back to the searching radar
          onGoOffline: () {
            viewModel.resetToOnline(); // Reset state first
            viewModel.toggleStatus();  // Then toggle them offline
          },
        );

      default:
        return const Center(child: CircularProgressIndicator());
    }
  }
}
