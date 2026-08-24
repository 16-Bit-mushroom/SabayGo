import 'package:flutter/material.dart';
import 'package:mobile_v2_uv_express/views/auth/welcome_screen.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/dispatcher_main_screen.dart';
import 'package:mobile_v2_uv_express/views/passenger_main_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      // home: const PassengerMainScreen()
      home: const WelcomeScreen()
    );
  }
}