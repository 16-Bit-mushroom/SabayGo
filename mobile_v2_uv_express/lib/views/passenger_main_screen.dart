import 'package:flutter/material.dart';
import 'home_search/home_screen.dart';

class PassengerMainScreen extends StatelessWidget {
  const PassengerMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          title: const Text(
            'SabayGo',
            style: TextStyle(
              color: Color(0xFF2D2059),
              fontWeight: FontWeight.bold,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          bottom: TabBar(
            indicatorColor: const Color(0xFF00A859),
            indicatorWeight: 3,
            labelColor: const Color(0xFF00A859),
            unselectedLabelColor: Colors.grey.shade500,
            tabs: const [
              Tab(icon: Icon(Icons.home_filled, size: 28)),
              Tab(icon: Icon(Icons.confirmation_number_outlined, size: 26)),
              Tab(icon: Icon(Icons.notifications_none, size: 28)),
              Tab(
                icon: CircleAvatar(
                  radius: 14,
                  // Mock Avatar - replace with actual user profile image later
                  backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=47'),
                  backgroundColor: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            HomeScreen(), // The newly simplified Home Screen
            Center(child: Text('My Reservations', style: TextStyle(fontSize: 18, color: Colors.grey))),
            Center(child: Text('Notifications', style: TextStyle(fontSize: 18, color: Colors.grey))),
            Center(child: Text('Profile Settings', style: TextStyle(fontSize: 18, color: Colors.grey))),
          ],
        ),
      ),
    );
  }
}