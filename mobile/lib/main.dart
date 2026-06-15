import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Make sure to add 'provider' to your pubspec.yaml
import 'core/theme/app_colors.dart';
import 'features/booking/infrastructure/mock_booking_repository.dart';
import 'features/booking/viewmodels/booking_viewmodel.dart';
import 'features/booking/presentation/screens/payment_screen.dart';
import 'features/booking/presentation/screens/driver_match_screen.dart';
import 'features/booking/presentation/screens/ride_selection_screen.dart';
import 'features/trip/presentation/screens/in_ride_screen.dart';

void main() {
  // 1. Initialize our decoupled Mock Repository
  final mockRepo = MockBookingRepository();

  // 2. Initialize our state manager
  final bookingViewModel = BookingViewModel(mockRepo);

  runApp(
    // We use ChangeNotifierProvider so any screen underneath can read the state
    ChangeNotifierProvider<BookingViewModel>.value(
      value: bookingViewModel,
      child: const SabayGoApp(),
    ),
  );
}

class SabayGoApp extends StatelessWidget {
  const SabayGoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Consumer looks up the widget tree for our active BookingViewModel instance
    return Consumer<BookingViewModel>(
      builder: (context, viewModel, child) {
        return MaterialApp(
          title: 'SabayGo',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.background,
            primaryColor: AppColors.primaryAction,
          ),
          // Conditionals dictate exactly which screen renders based on state
          // We use a Builder to get a context that exists INSIDE the MaterialApp
          home: Builder(
            builder: (innerContext) => _getHomeScreen(innerContext, viewModel),
          ),
        );
      },
    );
  }

  Widget _getHomeScreen(BuildContext context, BookingViewModel viewModel) {
    switch (viewModel.currentStep) {
      // Step 1: Start at the Ride Selection (Your correct starting point)
      case BookingStep.selectingRide:
        return RideSelectionScreen(
          selectedRideId: viewModel.selectedRideId,
          onBackPressed: () => debugPrint("Navigating back to main map..."),
          onRideSelected: (String id) => viewModel.selectRide(id),
          onConfirmRide: () => viewModel.proceedToPayment(), // Moves to Payment
        );

      // Step 2: The Payment Screen
      case BookingStep.selectingPayment:
        return PaymentScreen(
          selectedPaymentId:
              viewModel.selectedPaymentId, // Injects the current state
          isPromoApplied: viewModel.isPromoApplied,
          onBackPressed: () => viewModel.stepBack(), // Allows user to go back
          onPaymentMethodSelected: (String methodId) =>
              viewModel.selectPaymentMethod(methodId),
          onTogglePromo: () => viewModel.togglePromo(),
          onProceedToBook: () {
            // HEURISTIC #5: Error Prevention Check
            if (viewModel.selectedPaymentId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("⚠️ Please select a payment method to proceed.", style: TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.red.shade800,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.all(16),
                ),
              );
            } else {
              viewModel.requestRide("Matina Node", "Ulas Node");
            }
          },
        );

      // Step 3: The Loading Algorithm
      case BookingStep.matching:
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
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
          ),
        );

      // Step 4: The Final Match
      case BookingStep.matched:
        return DriverMatchScreen(
          driverName: viewModel.currentMatch!.driverName,
          vehicleModel: viewModel.currentMatch!.vehicleModel,
          plateNumber: viewModel.currentMatch!.plateNumber,
          vehicleColor: viewModel.currentMatch!.vehicleColor,
          rating: viewModel.currentMatch!.rating,

          currentPaymentId: viewModel.selectedPaymentId,
          onChangePayment: (String newMethod) => viewModel.selectPaymentMethod(newMethod),

          onBackPressed: () => viewModel.stepBack(), // Goes back to Payment
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
                      onPressed: () => Navigator.pop(
                        dialogContext,
                      ), // Close dialog, do nothing
                      child: const Text(
                        "Keep Ride",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext); // Close the dialog first
                        viewModel
                            .cancelRide(); // Tell the ViewModel to reset the state
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
          }, // Resets to Ride Selection
          onStartRide: () => viewModel.startRide(), // Moves to In-Ride Screen!
        );
      case BookingStep.inRide:
        return InRideScreen(
          onSosPressed: () => debugPrint("SOS Emergency Triggered!"),
          onBackPressed: () =>
              viewModel.stepBack(), // Allows peeking back at Driver detarils
        );
    }
  }
}
