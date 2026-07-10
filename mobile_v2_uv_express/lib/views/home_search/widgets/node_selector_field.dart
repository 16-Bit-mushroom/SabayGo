import 'package:flutter/material.dart';
import '../../../models/transit_node_model.dart';

class NodeSelectorField extends StatefulWidget {
  const NodeSelectorField({
    super.key,
    required this.hintText, // Changed from label to hintText
    required this.nodes,
    required this.selected,
    required this.onChanged,
    this.icon = Icons.location_on_outlined,
    this.iconColor,
  });

  final String hintText;
  final List<TransitNodeModel> nodes;
  final TransitNodeModel? selected;
  final ValueChanged<TransitNodeModel?> onChanged;
  final IconData icon;
  final Color? iconColor;

  @override
  State<NodeSelectorField> createState() => _NodeSelectorFieldState();
}

class _NodeSelectorFieldState extends State<NodeSelectorField> {
  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<TransitNodeModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NodePickerSheet(nodes: widget.nodes),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: Icon(widget.icon, color: widget.iconColor ?? theme.iconTheme.color),
          // ADDED: Clear button that only shows when a destination is selected
          suffixIcon: widget.selected != null
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    widget.onChanged(null); // Clears the input
                  },
                )
              : null,
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
        ),
        child: Text(
          // Logic: Show the node name if selected, otherwise show "Where to?"
          widget.selected?.name ?? widget.hintText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: widget.selected == null ? Colors.grey.shade600 : Colors.black87,
            fontWeight: widget.selected != null ? FontWeight.bold : FontWeight.w500,
            fontSize: 18, // Slightly larger font for that premium search bar feel
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// --- The Bottom Sheet Picker ---
class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({required this.nodes});
  final List<TransitNodeModel> nodes;

  @override
  State<_NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<_NodePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.nodes
        .where((n) => n.name.toLowerCase().contains(_query.toLowerCase()) || 
                      n.area.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(
                  'Select Destination',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true, // Automatically opens the keyboard
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search terminal or city',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final node = filtered[index];
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.grey),
                        title: Text(node.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(node.area),
                        onTap: () => Navigator.of(context).pop(node),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}