import 'package:flutter/material.dart';
import '../../../models/transit_node_model.dart';

class NodeSelectorField extends StatefulWidget {
  const NodeSelectorField({
    super.key,
    required this.label,
    required this.nodes,
    required this.selected,
    required this.onChanged,
    this.icon = Icons.location_on_outlined,
    this.iconColor, // ADDED: Allow custom icon colors
  });

  final String label;
  final List<TransitNodeModel> nodes;
  final TransitNodeModel? selected;
  final ValueChanged<TransitNodeModel?> onChanged;
  final IconData icon;
  final Color? iconColor; // ADDED: Variable to hold the color

  @override
  State<NodeSelectorField> createState() => _NodeSelectorFieldState();
}

class _NodeSelectorFieldState extends State<NodeSelectorField> {
  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<TransitNodeModel>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NodePickerSheet(label: widget.label, nodes: widget.nodes),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          // UPDATED: Use the passed iconColor, or default to theme icon color
          prefixIcon: Icon(widget.icon, color: widget.iconColor ?? theme.iconTheme.color),
          // UPDATED: Removed the OutlineInputBorder for a cleaner look
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        ),
        child: Text(
          widget.selected?.name ?? 'Select a node',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: widget.selected == null ? theme.hintColor : null,
            fontWeight: widget.selected != null ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// --- The Bottom Sheet Picker remains the same ---
class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({required this.label, required this.nodes});
  final String label;
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

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select ${widget.label}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search terminal or node',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }
}