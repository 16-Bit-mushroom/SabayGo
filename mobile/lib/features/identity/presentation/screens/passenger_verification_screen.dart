import 'package:flutter/material.dart';

class PassengerVerificationScreen extends StatefulWidget {
  const PassengerVerificationScreen({Key? key}) : super(key: key);

  @override
  State<PassengerVerificationScreen> createState() => _PassengerVerificationScreenState();
}

class _PassengerVerificationScreenState extends State<PassengerVerificationScreen> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  
  // Atomized Controllers for Step 1: Personal Info
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  
  final _dobController = TextEditingController();
  final _nationalityController = TextEditingController(text: "Filipino");
  final _phoneController = TextEditingController();
  String? _selectedGender;

  // Atomized Address Controllers
  final _streetController = TextEditingController();
  final _cityController = TextEditingController(text: "Davao City"); // Pre-filled for the corridor study
  final _provinceController = TextEditingController(text: "Davao del Sur");
  final _zipController = TextEditingController();

  // State for Step 2 & 3: Media
  bool _hasUploadedId = false;
  bool _hasUploadedProfilePic = false;
  bool _hasCompletedLiveness = false;
  bool _isProcessingValidation = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _dobController.dispose();
    _nationalityController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  // Native Date Picker Logic
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1), 
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2D2059), 
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  void _submitFullKYC() async {
    setState(() => _isProcessingValidation = true);

    // Simulate OCR parsing and Biometric face-matching delay
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;
    setState(() => _isProcessingValidation = false);

    _showSuccessModal();
  }

  void _showSuccessModal() {
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
                decoration: const BoxDecoration(color: Color(0xFFE5F6EE), shape: BoxShape.circle),
                child: const Icon(Icons.verified_user, color: Color(0xFF00A859), size: 64),
              ),
              const SizedBox(height: 24),
              const Text("Verification Complete!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "Your identity documents and liveness check have been successfully validated. You are now cleared to use the SabayGo network.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2059),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close sheet
                    Navigator.pop(context); // Return to Profile
                  },
                  child: const Text("Continue to App", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Identity Verification", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [

          SafeArea(
            child: 
          
          Theme(
            data: ThemeData(
              colorScheme: const ColorScheme.light(primary: Color(0xFF2D2059)),
            ),
            child: Stepper(
              type: StepperType.horizontal,
              currentStep: _currentStep,
              elevation: 0,
              controlsBuilder: (context, details) {
                final isLastStep = _currentStep == 2;
                return Padding(
                  padding: const EdgeInsets.only(top: 32.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLastStep ? _submitFullKYC : details.onStepContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2D2059),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            isLastStep ? "Submit Verification" : "Next Step", 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                          ),
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
                if (_currentStep == 0 && !_formKey.currentState!.validate()) return;
                if (_currentStep < 2) setState(() => _currentStep += 1);
              },
              onStepCancel: () {
                if (_currentStep > 0) setState(() => _currentStep -= 1);
              },
              steps: [
                // STEP 1: ATOMIZED PERSONAL DETAILS
                Step(
                  title: const Text("Details"),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                  content: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text("Full Name", style: TextStyle(color: Color(0xFF2D2059), fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildTextField("First Name", "e.g. Juan", controller: _firstNameController)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField("Last Name", "e.g. Dela Cruz", controller: _lastNameController)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField("Middle Name (Optional)", "e.g. Santos", controller: _middleNameController, isRequired: false),
                        const SizedBox(height: 32),

                        const Text("Details", style: TextStyle(color: Color(0xFF2D2059), fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "Date of Birth", 
                                "MM/DD/YYYY", 
                                controller: _dobController, 
                                readOnly: true, 
                                onTap: () => _selectDate(context)
                              )
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Gender", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _selectedGender,
                                    decoration: _inputDecoration("Select"),
                                    items: ["Male", "Female", "Other"].map((String value) {
                                      return DropdownMenuItem<String>(value: value, child: Text(value));
                                    }).toList(),
                                    onChanged: (newValue) => setState(() => _selectedGender = newValue),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(flex: 2, child: _buildTextField("Contact Number", "+63 9XX XXX XXXX", controller: _phoneController)),
                            const SizedBox(width: 16),
                            Expanded(flex: 1, child: _buildTextField("Nationality", "e.g. Filipino", controller: _nationalityController)),
                          ],
                        ),
                        const SizedBox(height: 32),

                        const Text("Current Address", style: TextStyle(color: Color(0xFF2D2059), fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildTextField("Street / House No. / Barangay", "e.g. Blk 1 Lot 2, Matina Crossing", controller: _streetController),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(flex: 2, child: _buildTextField("City/Municipality", "e.g. Davao City", controller: _cityController)),
                            const SizedBox(width: 16),
                            Expanded(flex: 1, child: _buildTextField("ZIP Code", "e.g. 8000", controller: _zipController)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField("Province", "e.g. Davao del Sur", controller: _provinceController),
                      ],
                    ),
                  ),
                ),
                
                // STEP 2: DOCUMENTS
                Step(
                  title: const Text("Upload ID"),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text("Government ID", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Passport, PhilID, or LTO License", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      _buildUploadBox(
                        title: "Tap to scan Government ID",
                        isUploaded: _hasUploadedId,
                        onTap: () => setState(() => _hasUploadedId = true),
                        onClear: () => setState(() => _hasUploadedId = false),
                      ),
                      const SizedBox(height: 24),
                      const Text("Public Profile Picture", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("This will be visible to matched carpoolers.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      _buildUploadBox(
                        title: "Tap to upload Profile Picture",
                        isUploaded: _hasUploadedProfilePic,
                        onTap: () => setState(() => _hasUploadedProfilePic = true),
                        onClear: () => setState(() => _hasUploadedProfilePic = false),
                      ),
                    ],
                  ),
                ),

                // STEP 3: LIVENESS CHECK
                Step(
                  title: const Text("Selfie"),
                  isActive: _currentStep >= 2,
                  content: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _hasCompletedLiveness ? const Color(0xFFE5F6EE) : const Color(0xFFF3F0FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _hasCompletedLiveness ? const Color(0xFF00A859) : const Color(0xFF2D2059).withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _hasCompletedLiveness ? Icons.face_retouching_natural : Icons.camera_front, 
                              size: 64, 
                              color: _hasCompletedLiveness ? const Color(0xFF00A859) : const Color(0xFF2D2059)
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _hasCompletedLiveness ? "Liveness Captured" : "Biometric Liveness Check",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _hasCompletedLiveness 
                                ? "Your facial scan is ready to be matched against your Government ID." 
                                : "We need to verify you are a real person. Ensure you are in a well-lit area and follow the on-screen prompts.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                            ),
                            const SizedBox(height: 24),
                            if (!_hasCompletedLiveness)
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Simulate the camera turning on and capturing
                                  setState(() => _hasCompletedLiveness = true);
                                },
                                icon: const Icon(Icons.camera_alt, color: Colors.white),
                                label: const Text("Start Camera Scan", style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D2059)),
                              )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ),

          // Loading Overlay for submission
          if (_isProcessingValidation)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Color(0xFF2D2059)),
                      SizedBox(height: 24),
                      Text("Validating Credentials...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 8),
                      Text("Matching Liveness scan against Government ID", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Refactored helper widget to support readOnly, onTap, and optional fields
  Widget _buildTextField(String label, String hint, {
    TextEditingController? controller, 
    bool isRequired = true, 
    bool readOnly = false, 
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          onTap: onTap,
          validator: (value) {
            if (isRequired && (value == null || value.trim().isEmpty)) {
              return "Required";
            }
            return null;
          },
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2D2059))),
    );
  }

  Widget _buildUploadBox({required String title, required bool isUploaded, required VoidCallback onTap, required VoidCallback onClear}) {
    if (!isUploaded) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00A859)),
      ),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.check, color: Color(0xFF00A859))),
          const SizedBox(width: 12),
          Expanded(child: Text("Document captured", style: TextStyle(color: Colors.grey.shade700, fontSize: 12))),
          IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: onClear)
        ],
      ),
    );
  }
}