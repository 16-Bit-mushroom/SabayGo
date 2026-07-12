import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transit_node_model.dart';
import '../../models/van_model.dart';

class PostScheduleScreen extends StatefulWidget {
  const PostScheduleScreen({super.key});

  @override
  State<PostScheduleScreen> createState() => _PostScheduleScreenState();
}

class _PostScheduleScreenState extends State<PostScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // --- Form State ---
  TransitNodeModel? _selectedOrigin;
  TransitNodeModel? _selectedDestination;
  VanModel? _selectedVan;
  String? _selectedDriverId;
  DateTime? _departureTime;
  final TextEditingController _fareCtrl = TextEditingController();

  // --- Mock Data (Usually comes from ViewModel) ---
  final List<TransitNodeModel> _terminals = const [
    TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City'),
    TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City'),
    TransitNodeModel(id: 'n5', name: 'Tagum City Terminal', area: 'Tagum City'),
  ];

  final List<VanModel> _allVans = [
    VanModel(id: 'v1', plateNumber: 'ABC-1234', registeredRouteNodeIds: ['n1', 'n2'], status: VanStatus.active),
    VanModel(id: 'v2', plateNumber: 'XYZ-9876', registeredRouteNodeIds: ['n1', 'n5'], status: VanStatus.active),
  ];

  final List<Map<String, String>> _drivers = [
    {'id': 'd1', 'name': 'Ricardo Dalisay'},
    {'id': 'd2', 'name': 'Juan Luna'},
  ];

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  // --- Core Compliance Logic ---
  List<VanModel> get _compliantVans {
    if (_selectedOrigin == null || _selectedDestination == null) return [];
    return _allVans.where((van) {
      return van.registeredRouteNodeIds.contains(_selectedOrigin!.id) &&
             van.registeredRouteNodeIds.contains(_selectedDestination!.id) &&
             van.status == VanStatus.active;
    }).toList();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00A859)),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00A859)),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;

    setState(() {
      _departureTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submitForm() {
    if (_formKey.currentState!.validate() && _departureTime != null) {
      // TODO: Save schedule to backend with audited Dispatcher ID
      // final newTrip = UvTripModel( ... );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule successfully posted!')),
      );
      Navigator.pop(context);
    } else if (_departureTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure date and time.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableVans = _compliantVans;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Post New Schedule', style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. Route Selection ---
                      const Text('ROUTE DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      
                      DropdownButtonFormField<TransitNodeModel>(
                        value: _selectedOrigin,
                        decoration: _inputDeco('Origin Terminal', Icons.trip_origin),
                        items: _terminals.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedOrigin = val;
                            _selectedVan = null; // Reset van if route changes
                          });
                        },
                        validator: (val) => val == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<TransitNodeModel>(
                        value: _selectedDestination,
                        decoration: _inputDeco('Destination Terminal', Icons.location_on_outlined),
                        items: _terminals.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedDestination = val;
                            _selectedVan = null; // Reset van if route changes
                          });
                        },
                        validator: (val) {
                          if (val == null) return 'Required';
                          if (val == _selectedOrigin) return 'Cannot be same as origin';
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // --- 2. Fleet Assignment ---
                      const Text('FLEET ASSIGNMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Only active vans registered for this specific route are shown.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<VanModel>(
                        value: _selectedVan,
                        decoration: _inputDeco('Assign Van', Icons.directions_car_outlined),
                        // Disable if origin/dest aren't selected, or if no compliant vans exist
                        items: availableVans.isEmpty ? null : availableVans.map((v) => DropdownMenuItem(value: v, child: Text('${v.plateNumber} (Cap: ${v.capacity})'))).toList(),
                        onChanged: (val) => setState(() => _selectedVan = val),
                        validator: (val) => val == null ? 'Please assign a compliant van' : null,
                        hint: Text(
                          _selectedOrigin == null || _selectedDestination == null 
                            ? 'Select route first' 
                            : availableVans.isEmpty ? 'No compliant vans available' : 'Select a van',
                          style: TextStyle(color: availableVans.isEmpty && _selectedOrigin != null ? Colors.red : null),
                        ),
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _selectedDriverId,
                        decoration: _inputDeco('Assign Driver', Icons.person_outline),
                        items: _drivers.map((d) => DropdownMenuItem(value: d['id'], child: Text(d['name']!))).toList(),
                        onChanged: (val) => setState(() => _selectedDriverId = val),
                        validator: (val) => val == null ? 'Required' : null,
                      ),

                      const SizedBox(height: 32),

                      // --- 3. Trip Details ---
                      const Text('TRIP DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),

                      InkWell(
                        onTap: _pickDateTime,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDeco('Departure Date & Time', Icons.access_time),
                          child: Text(
                            _departureTime == null 
                                ? 'Tap to select' 
                                : DateFormat('MMM dd, yyyy - hh:mm a').format(_departureTime!),
                            style: TextStyle(color: _departureTime == null ? Colors.grey.shade600 : Colors.black87, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _fareCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco('Standard Fare (PHP)', Icons.payments_outlined),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            
            // --- Post Button ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitForm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00A859),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Post Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper for consistent styling ---
  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A859), width: 2)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}