import 'package:flutter/material.dart';

import '../../../core/design/components/journey_strip.dart';
import '../../../core/design/components/picker_row.dart';
import '../../../core/design/components/sheet.dart';
import '../../../core/design/tokens.dart';
import '../../../models/transit_node_model.dart';

/// Picks one terminal, by tapping a row and searching a list.
///
/// Replaces two things. `node_selector_field.dart` had the searchable sheet
/// but was dead code — nothing imported it — and it hardcoded "Select
/// Destination" as its title, so it could never have asked for an origin.
/// `journey_picker_card.dart` then asked for both terminals with two
/// `DropdownButtonFormField`s side by side, which is where the real damage
/// was: two dropdowns sharing a phone's width gives each about 140 logical
/// pixels, and "Davao City Overland Terminal" does not fit in 140 pixels.
/// Both fields showed an ellipsis, so the passenger chose their journey from
/// two lists of truncated names.
///
/// Full width, one at a time, and searchable. The sheet also shows each
/// terminal's city, which is the difference between two similarly-named
/// terminals that a truncated dropdown row could not show at all.
class TerminalPickerField extends StatelessWidget {
  const TerminalPickerField({
    required this.end,
    required this.label,
    required this.sheetTitle,
    required this.value,
    required this.nodes,
    required this.onChanged,
    super.key,
  });

  /// Boarding or alighting — draws the matching marker, so the form and the
  /// ticket it produces use one visual language.
  final JourneyEnd end;

  /// "From" / "To".
  final String label;

  /// Asked as a question in the sheet: people answer questions more readily
  /// than they parse labels.
  final String sheetTitle;

  final TransitNodeModel? value;
  final List<TransitNodeModel> nodes;
  final ValueChanged<TransitNodeModel> onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<TransitNodeModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TerminalSheet(
        title: sheetTitle,
        nodes: nodes,
        selected: value,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppPickerRow(
      leading: JourneyMarker(end),
      label: label,
      value: value?.name,
      placeholder: 'Choose a terminal',
      semanticHint: 'Opens the terminal list',
      onTap: () => _open(context),
    );
  }
}

class _TerminalSheet extends StatefulWidget {
  const _TerminalSheet({
    required this.title,
    required this.nodes,
    required this.selected,
  });

  final String title;
  final List<TransitNodeModel> nodes;
  final TransitNodeModel? selected;

  @override
  State<_TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends State<_TerminalSheet> {
  String _query = '';

  List<TransitNodeModel> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.nodes;
    return widget.nodes
        .where((n) =>
            n.name.toLowerCase().contains(q) ||
            n.area.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;

    return AppSheet(
      title: widget.title,
      subtitle: 'Terminals only — UV Express picks up at fixed points.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.md,
            ),
            child: TextField(
              // Not autofocused. The list is short enough to read, and a
              // keyboard that appears unasked covers most of it.
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search terminal or city',
                isDense: true,
              ),
            ),
          ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxxl,
              ),
              child: Text(
                'No terminal matches “$_query”. A2Z serves fixed LTFRB '
                'routes, so only terminals on those routes appear here.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: matches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final node = matches[i];
                  final isSelected = node == widget.selected;
                  return ListTile(
                    // `selected` is what tells a screen reader this is the
                    // current choice; the tick is for everyone else.
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    title: Text(
                      node.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: node.area.isEmpty ? null : Text(node.area),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(node),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
