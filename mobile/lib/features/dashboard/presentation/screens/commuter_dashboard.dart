import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/presentation/screens/driver_match_screen.dart';
import 'package:mobile/features/booking/presentation/screens/payment_screen.dart';
import 'package:mobile/features/booking/presentation/screens/ride_selection_screen.dart';
import 'package:mobile/features/booking/viewmodels/booking_viewmodel.dart';
import 'package:mobile/features/communications/presentations/screens/chat_detail_screen.dart';
import 'package:mobile/features/communications/presentations/screens/messages_screen.dart';
import 'package:mobile/features/dashboard/presentation/screens/subscription_paywall_modal.dart';
import 'package:mobile/features/dashboard/presentation/widgets/node_selection_hud.dart';
import 'package:mobile/features/identity/presentation/screens/edit_profile_screen.dart';
import 'package:mobile/features/identity/presentation/screens/login_screen.dart';
import 'package:mobile/features/identity/presentation/screens/passenger_verification_screen.dart';
import 'package:mobile/features/identity/presentation/screens/profile_screen.dart';
import 'package:mobile/features/identity/viewmodels/profile_viewmodel.dart';
import 'package:mobile/features/trip/presentation/screens/in_ride_screen.dart';
import 'package:mobile/features/trip/presentation/screens/trip_completed_screen.dart';
import 'package:mobile/features/trip/presentation/screens/trip_history_screen.dart';
import 'package:provider/provider.dart';
import 'package:mobile/features/booking/presentation/screens/location_search_screen.dart';

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

    if (_currentIndex == 2) return const MessagesScreen();
    if (_currentIndex == 2)
      return const Center(child: Text("Saved Routes/Promo"));

    if (_currentIndex == 3) {
      return ProfileScreen(
        // UPDATE THIS LINE:
        onEditProfile: () {
          final currentUser = context.read<ProfileViewModel>().currentUser;
          
          // Split the existing full name into First and Last to fit the new UI
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
                  // Mocking the required backend formats so the form doesn't instantly throw errors
                  'email': 'juan@example.edu.ph', 
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
          context.read<BookingViewModel>().reset();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        },
      );
    }

    // Index 0 (Home) runs your state machine
    switch (viewModel.currentStep) {

      case BookingStep.idle:
        return _buildHomeMapState(context);

      case BookingStep.selectingRide:
        return RideSelectionScreen(
          selectedRideId: viewModel.selectedRideId,
          onBackPressed: () {
            // Reset to the idle map state
            viewModel.reset(); 
            // Immediately slide up the location search screen again
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LocationSelectionScreen()),
            );
          },
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
          vehicleModel: viewModel.currentMatch!.vehicleModel.split(' - ').first,
          plateNumber: viewModel.currentMatch!.vehiclePlate,
          vehicleColor: viewModel.currentMatch!.vehicleModel.split(' - ').length > 1 
              ? viewModel.currentMatch!.vehicleModel.split(' - ').last 
              : "Standard",
          rating: viewModel.currentMatch!.driverRating.toStringAsFixed(1), 
          onBackPressed: () {}, // Intentionally empty to prevent accidental back-outs
          
          // 1. WIRE UP THE MESSAGE BUTTON
          onMessageDriver: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  receiverName: viewModel.currentMatch!.driverName,
                  role: "Driver", // Hardcoded role since this is the driver match screen
                ),
              ),
            );
          },
          
          // 2. WIRE UP THE CALL BUTTON (Simulated VoIP Dialer)
          onCallDriver: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
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
                      "Calling ${viewModel.currentMatch!.driverName.split(' ').first}...",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text("Secure VoIP connection", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 32),
                    FloatingActionButton(
                      backgroundColor: Colors.red,
                      elevation: 0,
                      onPressed: () => Navigator.pop(context), // Hangs up the call
                      child: const Icon(Icons.call_end, color: Colors.white),
                    )
                  ],
                ),
              ),
            );
          },
          
          onCancelRide: () {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                return AlertDialog(
                  backgroundColor: const Color(0xFFFAFAFA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text("Cancel Ride?", style: TextStyle(fontWeight: FontWeight.bold)),
                  content: const Text("Are you sure you want to cancel this request? You may be charged a cancellation fee."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text("Keep Ride", style: TextStyle(color: Colors.grey)),
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
                      child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
          onBackPressed: () {}, // FIXED: Empty callback prevents accidental backing out of a live ride
          onSimulateDropoff: () {
            // DO NOT save to database here. 
            // Just transition the UI to the receipt screen.
            viewModel.finishRide(); 
          },
        );

      case BookingStep.completed:
        return TripCompletedScreen(
          driverName: viewModel.currentMatch?.driverName ?? "Driver",
          origin: _pickupNode?.name ?? "Origin",
          destination: _dropoffNode?.name ?? "Destination",
          onReturnHome: () {
            // 1. Reset the ViewModel State Machine
            viewModel.reset();
            
            // 2. Clear the local Node Selection HUD
            setState(() {
              _pickupNode = null;
              _dropoffNode = null;
            });
            
            // 3. Show Success Message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("P2P settlement complete. Ready for your next ride!"),
                  backgroundColor: const Color(0xFF00A859), // Success Green
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          },
        );

      default:
        return const Center(child: CircularProgressIndicator());
  }
  }


  Widget _buildHomeMapState(BuildContext context) {
    return Stack(
      children: [
        // 1. Mock Map Background
        Positioned.fill(
          child: Container(
            color: AppColors.highlight.withOpacity(0.2), 
            child: const Center(
              child: Text(
                "🗺️ Live Map Active\n(McArthur Highway Corridor Geofenced)", 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.grey)
              ),
            ),
          ),
        ),
        
        // 2. THE TOP APP BAR (Floating)
        Positioned(
          top: 60,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: Row(
              children: [
                const Icon(Icons.menu, color: Color(0xFF2D2059)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _hasActiveSaaS ? "SabayGo · Subscribed" : "SabayGo · Free Tier", 
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2059))
                  ),
                ),
                const CircleAvatar(radius: 16, backgroundColor: Colors.blue, child: Icon(Icons.person, size: 16, color: Colors.white)),
              ],
            ),
          ),
        ),

        // 3. THE STRICT NODE SELECTION HUD (Replaces the old 'Where to?' bar)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: NodeSelectionHud(
              selectedPickup: _pickupNode,
              selectedDropoff: _dropoffNode,
              onSelectPickup: (node) => setState(() => _pickupNode = node),
              onSelectDropoff: (node) => setState(() => _dropoffNode = node),
              onRequestRide: _handleRequestRide, // This triggers your eKYC and SaaS gates!
            ),
          ),
        ),
      ],
    );
  }


  // THE INTERCEPTOR MODAL
  void _showVerificationRequiredModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.security_update_warning, color: Colors.orange, size: 48),
              ),
              const SizedBox(height: 16),
              const Text("Action Required", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "To maintain community safety, all commuters must submit a valid Government ID before requesting a seat on the SabayGo network.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2059),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close the modal
                    // Push the user directly to the verification screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PassengerVerificationScreen()),
                    );
                  },
                  child: const Text("Verify Identity Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("I'll do it later", style: TextStyle(color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Inside _CommuterDashboardState

CarpoolNode? _pickupNode;
CarpoolNode? _dropoffNode;

// MOCK FLAGS FOR CAPSTONE DEFENSE:
bool _isVerified = true;       // Intercepts eKYC if false
bool _hasActiveSaaS = false;    // Intercepts Paywall if false

void _handleRequestRide() {
    // Gate 1: Check eKYC Identity Verification
    if (!_isVerified) {
      _showVerificationRequiredModal(context);
      return;
    }

    // Gate 2: Check SaaS Zero-Commission Subscription
    if (!_hasActiveSaaS) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SubscriptionPaywallModal(
          onSubscribeSuccess: () {
            setState(() => _hasActiveSaaS = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("SaaS Subscription Activated! Searching for matched drivers..."), backgroundColor: Color(0xFF00A859)),
            );
          },
        ),
      );
      return;
    }

    // 3. All gates cleared! Trigger the NAHGM matching state
    if (_pickupNode != null && _dropoffNode != null) {
      // Read the view model and trigger the matching process
      context.read<BookingViewModel>().requestRide(
        _pickupNode!.name, 
        _dropoffNode!.name
      );
    }
  }
}
