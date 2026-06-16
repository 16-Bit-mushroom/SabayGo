import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import 'core/theme/app_colors.dart';
import 'features/booking/infrastructure/mock_booking_repository.dart';
import 'features/booking/viewmodels/booking_viewmodel.dart';
import 'features/dashboard/presentation/screens/commuter_dashboard.dart';

void main() {
  // 1. Initialize our decoupled Mock Repository
  final mockRepo = MockBookingRepository();

  // 2. Initialize our state manager
  final bookingViewModel = BookingViewModel(mockRepo);

  runApp(
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
    return MaterialApp(
      title: 'SabayGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryAction,
      ),
      // We route directly to the global dashboard now
      home: const CommuterDashboard(),
    );
  }
}