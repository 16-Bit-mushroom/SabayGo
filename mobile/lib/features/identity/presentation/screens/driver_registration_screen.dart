import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({Key? key}) : super(key: key);

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  int _currentStep = 0;
  
  // Controllers for mock data extraction
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  
  // State for capacity toggle
  int _seatingCapacity = 2;

  void _submitKYC() {
    // Show a success modal instead of navigating immediately
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 64),
              ),
              const SizedBox(height: 24),
              const Text("Documents Submitted!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "Your driver application is now under review. We will notify you once your compliance checks are cleared.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    Navigator.pop(context); // Close sheet
                    Navigator.pop(context); // Return to Profile
                  },
                  child: const Text("Return to Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Driver Registration", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 2;
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLastStep ? _submitKYC : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAction,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(isLastStep ? "Submit Application" : "Continue", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text("Back", style: TextStyle(color: Colors.grey)),
                  ),
                ]
              ],
            ),
          );
        },
        onStepContinue: () {
          if (_currentStep < 2) setState(() => _currentStep += 1);
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep -= 1);
        },
        steps: [
          Step(
            title: const Text("Personal Verification", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("Driver's License details"),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                const SizedBox(height: 16),
                _buildTextField("Driver's License Number", "e.g., N01-12-123456", controller: _licenseController),
                const SizedBox(height: 16),
                _buildTextField("Expiration Date", "MM/DD/YYYY"),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid), borderRadius: BorderRadius.circular(12)),
                  child: const Column(
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 32, color: Colors.grey),
                      SizedBox(height: 8),
                      Text("Tap to upload front of license", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text("Vehicle Information", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("Make, model, and capacity"),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildTextField("Vehicle Make & Model", "e.g., Toyota Vios"),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTextField("Plate Number", "ABC-1234", controller: _plateController)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField("Color", "e.g., Silver")),
                  ],
                ),
                const SizedBox(height: 24),
                const Text("Available Carpool Seats", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [1, 2, 3, 4].map((capacity) {
                    final isSelected = _seatingCapacity == capacity;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _seatingCapacity = capacity),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryAction : Colors.white,
                            border: Border.all(color: isSelected ? AppColors.primaryAction : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              capacity.toString(),
                              style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Step(
            title: const Text("Terms & Agreement", style: TextStyle(fontWeight: FontWeight.bold)),
            isActive: _currentStep >= 2,
            content: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "By submitting this application, you agree to SabayGo's Cost-Sharing Agreement. SabayGo is a carpooling platform designed for sharing fuel costs, not for commercial profit.",
                          style: TextStyle(color: Colors.black87, fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildTextField(String label, String hint, {TextEditingController? controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.grey.shade300)
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.grey.shade300)
            ),
            // FIXED: Removed the 'const' keyword right here
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: AppColors.primaryAction)
            ),
          ),
        ),
      ],
    );
  }
}