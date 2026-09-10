import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../models/transit_node_model.dart';
import '../../../viewmodels/home_search_viewmodel.dart';

/// Origin, destination and date — everything a search needs.
///
/// Replaces WhereToCard, which asked only for a destination. The server
/// requires both stops: a trip has no single fare or availability until
/// the journey is known, because both are properties of the sections of
/// road travelled. Ecoland→Digos and Ecoland→Cotabato are different
/// prices on the same van.
class JourneyPickerCard extends StatelessWidget {
  const JourneyPickerCard({super.key, required this.vm});

  final HomeSearchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final blocked = vm.searchBlockedReason;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (vm.isLoadingTerminals)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _TerminalField(
                      label: 'From',
                      icon: Icons.trip_origin,
                      iconColour: AppColors.accent,
                      value: vm.selectedOrigin,
                      nodes: vm.nodes,
                      onChanged: vm.setOrigin,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Swap',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: vm.swapNodes,
                  ),
                  Expanded(
                    child: _TerminalField(
                      label: 'To',
                      icon: Icons.place,
                      iconColour: AppColors.danger,
                      value: vm.selectedDestination,
                      nodes: vm.nodes,
                      onChanged: vm.setDestination,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(context),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        DateFormat('EEE, d MMM').format(vm.serviceDate),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: vm.canSearch && !vm.isLoadingTrips
                          ? vm.search
                          : null,
                      icon: vm.isLoadingTrips
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search, size: 20),
                      label: const Text('Search'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
              // Says why the button is disabled rather than leaving the
              // person to guess. The direction case matters: routes are
              // one-way sequences, so Cotabato→Ecoland is a different
              // route, not this one reversed.
              if (blocked != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        blocked,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.serviceDate,
      firstDate: now,
      // Matches advance_booking_open_days on the server. A date beyond
      // it would return nothing and look like a fault.
      lastDate: now.add(const Duration(days: 7)),
    );
    if (picked != null) vm.setServiceDate(picked);
  }
}

class _TerminalField extends StatelessWidget {
  const _TerminalField({
    required this.label,
    required this.icon,
    required this.iconColour,
    required this.value,
    required this.nodes,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color iconColour;
  final TransitNodeModel? value;
  final List<TransitNodeModel> nodes;
  final ValueChanged<TransitNodeModel?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TransitNodeModel>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: Icon(icon, size: 18, color: iconColour),
      ),
      hint: const Text('Select', style: TextStyle(fontSize: 13)),
      items: [
        for (final node in nodes)
          DropdownMenuItem(
            value: node,
            child: Text(
              node.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}