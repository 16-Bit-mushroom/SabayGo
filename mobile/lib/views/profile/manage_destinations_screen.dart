import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/empty_state.dart';
import '../../core/design/tokens.dart';
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
      backgroundColor: AppColors.surfaceRaised,
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
                Text('Add a destination', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'For example, "Mom\'s house".',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Give this place a name.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: AppSizing.primaryActionHeight,
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
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surfaceRaised))
                        : const Text('Save destination'),
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
      appBar: AppBar(
        title: const Text('Saved destinations'),
        actions: [
          IconButton(
            tooltip: 'Add a destination',
            onPressed: _showAddDestinationSheet,
            icon: const Icon(Icons.add),
          )
        ],
      ),
      body: SafeArea(
        child: destinations.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                itemCount: destinations.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.edge),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: AppColors.brandContainer, shape: BoxShape.circle),
                            child: const Icon(Icons.location_on, color: AppColors.brand, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dest.label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                if (dest.address != null && dest.address!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(dest.address!, style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ${dest.label}',
                            onPressed: () => _deleteDestination(dest),
                            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
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
    return AppEmptyState(
      icon: Icons.bookmark_outline,
      title: 'No saved destinations yet',
      body: 'Save the places you often ride to, and you will hear when a van runs there.',
      action: FilledButton.icon(
        onPressed: _showAddDestinationSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add a destination'),
      ),
    );
  }
}
