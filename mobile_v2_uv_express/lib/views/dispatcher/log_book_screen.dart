import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../viewmodels/dispatcher/log_book_viewmodel.dart';

class LogBookScreen extends StatefulWidget {
  const LogBookScreen({super.key});

  @override
  State<LogBookScreen> createState() => _LogBookScreenState();
}

class _LogBookScreenState extends State<LogBookScreen> {
  final LogBookViewModel _viewModel = LogBookViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- NEW: Search Bar ---
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search name, number, or van...',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _viewModel.setSearchQuery,
          ),
        ),

        // --- Filter Chips ---
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _viewModel.availableFilters.map((filter) {
                final isSelected = _viewModel.activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) _viewModel.setFilter(filter);
                    },
                    selectedColor: const Color(0xFF00A859).withOpacity(0.2),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF00A859) : Colors.grey.shade700,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // --- Log Book Entries ---
        Expanded(
          child: _viewModel.filteredEntries.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _viewModel.filteredEntries.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = _viewModel.filteredEntries[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.passengerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                DateFormat('MMM dd, hh:mm a').format(entry.date),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(Icons.phone_outlined, entry.contactNumber),
                          const SizedBox(height: 4),
                          _buildDetailRow(Icons.home_outlined, entry.address),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.vanPlateNumber, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2059))),
                              Row(
                                children: [
                                  const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(entry.destinationName, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Add this helper method inside the _LogBookScreenState class:
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No log entries found',
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}