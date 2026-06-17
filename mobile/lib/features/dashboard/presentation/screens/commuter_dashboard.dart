import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/presentation/screens/driver_match_screen.dart';
import 'package:mobile/features/booking/presentation/screens/payment_screen.dart';
import 'package:mobile/features/booking/presentation/screens/ride_selection_screen.dart';
import 'package:mobile/features/booking/viewmodels/booking_viewmodel.dart';
import 'package:mobile/features/identity/presentation/screens/login_screen.dart';
import 'package:mobile/features/identity/presentation/screens/profile_screen.dart';
import 'package:mobile/features/trip/presentation/screens/in_ride_screen.dart';
import 'package:mobile/features/trip/presentation/screens/trip_completed_screen.dart';
import 'package:mobile/features/trip/presentation/screens/trip_history_screen.dart';
import 'package:provider/provider.dart';

class CommuterDashboard extends StatefulWidget {
  const CommuterDashboard({Key? key}) : super(key: key);

  @override
  State<CommuterDashboard> createState() => _CommuterDashboardState();
}

class _CommuterDashboardState extends State<CommuterDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Watch the ViewModel to rebuild when state changes
    final viewModel = context.watch<BookingViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildBody(context, viewModel),

      // The Global Navigation Bar
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
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, BookingViewModel viewModel) {
    // Handle tab switching
    if (_currentIndex == 1) return const TripHistoryScreen();

    if (_currentIndex == 2) return const Center(child: Text("Messages UI"));
    if (_currentIndex == 2)
      return const Center(child: Text("Saved Routes/Promo"));

    if (_currentIndex == 3) {
      return ProfileScreen(
        onEditProfile: () => debugPrint("Edit Profile Tapped"),
        onSettingsTap: (setting) => debugPrint("$setting Tapped"),
        onSignOut: () {
          // 1. WIPE THE STATE CLEAN! 
          // (Requires importing 'package:provider/provider.dart' at the top if not already there)
          context.read<BookingViewModel>().reset();
          
          // 2. Log out and return to the Unified Login Bridge
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        },
      );
    }

    // Index 0 (Home) runs your state machine
    switch (viewModel.currentStep) {
      case BookingStep.selectingRide:
        return RideSelectionScreen(
          selectedRideId: viewModel.selectedRideId,
          onBackPressed: () => debugPrint("Navigating back to main map..."),
          onRideSelected: (String id) => viewModel.selectRide(id),
          onConfirmRide: () => viewModel.proceedToPayment(),
        );

      case BookingStep.selectingPayment:
        return PaymentScreen(
          selectedPaymentId: viewModel.selectedPaymentId,
          isPromoApplied: viewModel.isPromoApplied,
          onBackPressed: () => viewModel.stepBack(),
          onPaymentMethodSelected: (String methodId) =>
              viewModel.selectPaymentMethod(methodId),
          onTogglePromo: () => viewModel.togglePromo(),
          onProceedToBook: () {
            if (viewModel.selectedPaymentId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    "⚠️ Please select a payment method to proceed.",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.red.shade800,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(16),
                ),
              );
            } else {
              viewModel.requestRide("Matina Node", "Ulas Node");
            }
          },
        );

      case BookingStep.matching:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primaryAction),
              SizedBox(height: 24),
              Text(
                "Running NAHGM Algorithm...\nMatching optimal nodes.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );

      case BookingStep.matched:
        return DriverMatchScreen(
          driverName: viewModel.currentMatch!.driverName,
          vehicleModel: viewModel.currentMatch!.vehicleModel,
          plateNumber: viewModel.currentMatch!.plateNumber,
          vehicleColor: viewModel.currentMatch!.vehicleColor,
          rating: viewModel.currentMatch!.rating,
          currentPaymentId: viewModel.selectedPaymentId,
          onChangePayment: (String newMethod) =>
              viewModel.selectPaymentMethod(newMethod),
          onBackPressed: () => viewModel.stepBack(),
          onMessageDriver: () => debugPrint("Opening chat..."),
          onCallDriver: () => debugPrint("Initiating VoIP call..."),
          onCancelRide: () {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    "Cancel Ride?",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: const Text(
                    "Are you sure you want to cancel this request? You may be charged a cancellation fee.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        "Keep Ride",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        viewModel.cancelRide();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        elevation: 0,
                      ),
                      child: const Text(
                        "Yes, Cancel",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          onStartRide: () => viewModel.startRide(),
        );

      case BookingStep.inRide:
        return InRideScreen(
          onSosPressed: () => debugPrint("SOS Emergency Triggered!"),
          onBackPressed: () => debugPrint("Removed back button"),
          onSimulateDropoff: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("📍 Arriving at destination..."),
                backgroundColor: AppColors.primaryAction,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
            await Future.delayed(const Duration(seconds: 3));
            viewModel.completeRide();
          },
        );

      case BookingStep.completed:
        return TripCompletedScreen(onReturnHome: () => viewModel.resetToHome());

      default:
        return const Center(child: CircularProgressIndicator());
    }
  }
}
