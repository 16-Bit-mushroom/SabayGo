import 'package:flutter/material.dart';
import 'theme/app_colors.dart';
import 'ui/screens/driver_trip_history_screen.dart';

void main() {
  runApp(const SabayGoApp());
}

class SabayGoApp extends StatelessWidget {
  const SabayGoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabayGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: AppColors.background),
      home: const MockDriverTripHistoryViewModel(), 
    );
  }
}

class MockDriverTripHistoryViewModel extends StatefulWidget {
  const MockDriverTripHistoryViewModel({Key? key}) : super(key: key);

  @override
  State<MockDriverTripHistoryViewModel> createState() => _MockDriverTripHistoryViewModelState();
}

class _MockDriverTripHistoryViewModelState extends State<MockDriverTripHistoryViewModel> {
  bool _isFilterExpanded = false;
  String _activeFilter = "All";

  @override
  Widget build(BuildContext context) {
    return DriverTripHistoryScreen(
      isFilterExpanded: _isFilterExpanded,
      onToggleFilter: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
      activeFilter: _activeFilter,
      onSelectFilter: (filter) => setState(() => _activeFilter = filter),
    );
  }
}