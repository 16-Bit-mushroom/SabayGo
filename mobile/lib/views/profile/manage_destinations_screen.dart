import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/saved_destination_model.dart';
import '../../viewmodels/profile_viewmodel.dart';

class ManageDestinationsScreen extends StatefulWidget {
  const ManageDestinationsScreen({super.key});

  @override
  State<ManageDestinationsScreen> createState() => _ManageDestinationsScreenState();
}

class _ManageDestinationsScreenState extends State<ManageDestinationsScreen> {
  Future<void> _deleteDestination(SavedDestinationModel dest) async {
    final message =
        await context.read<ProfileViewModel>().removeSavedDestination(dest.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? 'Destination removed')),
    );
  }

  Future<void> _showAddDestinationSheet() async {
    final labelCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Destination', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Label (e.g. "Mom\'s house")',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'Address (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() => saving = true);
                            final message = await context
                                .read<ProfileViewModel>()
                                .addSavedDestination(
                                  label: labelCtrl.text.trim(),
                                  address: addressCtrl.text.trim(),
                                );
                            if (message != null) {
                              setSheetState(() {
                                saving = false;
                                error = message;
                              });
                              return;
                            }
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00A859),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = context.watch<ProfileViewModel>().savedDestinations;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Saved Destinations', style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            onPressed: _showAddDestinationSheet,
            icon: const Icon(Icons.add, color: Color(0xFF00A859)),
          )
        ],
      ),
      body: SafeArea(
        child: destinations.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: destinations.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFFD9534F).withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.location_on, color: Color(0xFFD9534F), size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dest.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                if (dest.address != null && dest.address!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(dest.address!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _deleteDestination(dest),
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No saved destinations yet', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Add places you frequently travel to.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}
