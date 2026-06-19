import 'package:flutter/material.dart';
import 'package:mobile/features/dashboard/presentation/screens/commuter_dashboard.dart';
import 'package:provider/provider.dart';
import '../../../../core/domain/models/user_model.dart';
import '../../viewmodels/profile_viewmodel.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController(); // Only for UI simulation
  bool _obscurePassword = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignUp() async {
    if (_formKey.currentState!.validate()) {
      // 1. Generate a unique ID (Mocking a UUID for the prototype)
      final newUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      // 2. Create the new UserModel
      // We pass empty strings for emergency contacts to be filled later via Edit Profile
      final newUser = UserModel(
        id: newUserId,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        emergencyContactName: 'Pending Setup',
        emergencyContactPhone: 'Pending Setup',
        accountType: 'Passenger',
        subscriptionTier: 'Free',
        rating: 5.0, // Start with perfect rating
        joinDate: 'Today',
        totalTrips: 0,
        co2Saved: '0 kg',
        availableVouchers: 1, // Welcome bonus
      );

      // 3. Save to Database via ViewModel
      await context.read<ProfileViewModel>().registerUser(newUser);

      // 4. Navigate directly to the Dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CommuterDashboard()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Create Account", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2D2059))),
              const SizedBox(height: 8),
              const Text("Join SabayGo and start your journey.", style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                      decoration: _inputDecoration(Icons.person_outline, "First Name"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                      decoration: _inputDecoration(null, "Last Name"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email is required";
                  if (!value.endsWith(".edu.ph")) return "Must be a valid .edu.ph address";
                  return null;
                },
                decoration: _inputDecoration(Icons.school_outlined, "University Email"),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (value) {
                   if (value == null || value.isEmpty) return "Required";
                   final clean = value.replaceAll(' ', '');
                   if (!(clean.startsWith('09') && clean.length == 11) && 
                       !(clean.startsWith('+639') && clean.length == 13)) {
                     return "Valid PH format required";
                   }
                   return null;
                },
                decoration: _inputDecoration(Icons.phone_outlined, "Phone Number"),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: (value) => value == null || value.length < 6 ? "Minimum 6 characters" : null,
                decoration: InputDecoration(
                  hintText: "Password",
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2D2059), width: 2)),
                ),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleSignUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2059),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text("Sign Up", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData? icon, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade500) : null,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2D2059), width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
    );
  }
}