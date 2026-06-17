import 'package:flutter/material.dart';
import 'package:mobile/features/trip/viewmodels/trip_history_viewmodel.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';

// View Models
import 'features/booking/infrastructure/mock_booking_repository.dart';
import 'features/booking/viewmodels/booking_viewmodel.dart';
import 'features/booking/viewmodels/driver_viewmodel.dart';
import 'features/identity/viewmodels/profile_viewmodel.dart'; // NEW

// Dashboards
import 'features/dashboard/presentation/screens/commuter_dashboard.dart';
import 'features/dashboard/presentation/screens/driver_dashboard.dart';

// Identity
import 'features/identity/presentation/screens/login_screen.dart';

void main() {
  // 1. Initialize our decoupled Mock Repository
  final mockRepo = MockBookingRepository();

  // 2. Initialize our state manager

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BookingViewModel(mockRepo)),
        ChangeNotifierProvider(create: (_) => DriverViewModel()), // NEW
        ChangeNotifierProvider(create: (_) => ProfileViewModel()),
        ChangeNotifierProvider(create: (_) => TripHistoryViewModel()),
      ],
      child: const SabayGoApp(),
    ),
  );
}

class SabayGoApp extends StatelessWidget {
  const SabayGoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabayGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryAction,
      ),
      // We route directly to the global dashboard now
      // home: const CommuterDashboard(),
      home: const LoginScreen(),
    );
  }
}
