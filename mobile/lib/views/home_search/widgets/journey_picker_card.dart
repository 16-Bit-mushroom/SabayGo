import 'package:flutter/material.dart';

import '../../../core/design/components/app_card.dart';
import '../../../core/design/components/journey_strip.dart';
import '../../../core/design/components/picker_row.dart';
import '../../../core/design/tokens.dart';
import '../../../core/util/when.dart';
import '../../../viewmodels/home_search_viewmodel.dart';
import 'terminal_picker_field.dart';

/// The search form: where from, where to, which day.
///
/// The three questions are now stacked full width in one card, sharing a
/// rail, rather than being two truncating dropdowns beside each other with
/// a date button underneath. Reading down the card describes the journey in
/// the order a person thinks it — get on here, get off there, on this day.
///
/// The swap control sits on the line between the two terminals, which is
/// the only place it can be where its meaning needs no label: it exchanges
/// the thing above for the thing below.
class JourneyPickerCard extends StatelessWidget {
  const JourneyPickerCard({super.key, required this.vm});

  final HomeSearchViewModel vm;

  /// Where the text starts, so the divider between two rows begins there
  /// too and the markers read as one rail.
  static const double _textInset =
      AppSpacing.lg + AppPickerRow.leadingWidth + AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final blocked = vm.searchBlockedReason;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: vm.isLoadingTerminals ? _loading() : _form(context),
          ),
          // No Search button (12 Nov): the departures follow the journey as
          // soon as both ends are chosen. What is still missing is said
          // here, so an empty list never leaves the person guessing. The
          // direction case matters: routes are one-way sequences, so
          // Cotabato→Ecoland is a different route, not this one reversed.
          if (blocked != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Note(blocked),
          ],
        ],
      ),
    );
  }

  Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.section),
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _form(BuildContext context) => Column(
        children: [
          TerminalPickerField(
            end: JourneyEnd.boarding,
            label: 'From',
            sheetTitle: 'Where are you boarding?',
            value: vm.selectedOrigin,
            nodes: vm.nodes,
            onChanged: vm.setOrigin,
          ),
          _SwapRow(onSwap: vm.swapNodes),
          TerminalPickerField(
            end: JourneyEnd.alighting,
            label: 'To',
            sheetTitle: 'Where are you going?',
            value: vm.selectedDestination,
            nodes: vm.nodes,
            onChanged: vm.setDestination,
          ),
          const Divider(height: 1, indent: _textInset),
          _DayChips(
            selected: vm.serviceDate,
            onSelected: vm.setServiceDate,
            onPick: () => _pickDate(context),
          ),
        ],
      );

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.serviceDate,
      firstDate: now,
      // Matches advance_booking_open_days on the server. A date beyond it
      // would return nothing and look like a fault.
      lastDate: now.add(const Duration(days: 7)),
      helpText: 'Which day are you travelling?',
    );
    if (picked != null) vm.setServiceDate(picked);
  }
}

/// The divider between the two terminals, carrying the swap control.
class _SwapRow extends StatelessWidget {
  const _SwapRow({required this.onSwap});

  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(height: 1, indent: JourneyPickerCard._textInset),
        ),
        IconButton(
          // Both a tooltip and a semantic label: the tooltip is for a
          // long press, the label for a screen reader, and an icon-only
          // control needs to answer both.
          tooltip: 'Swap From and To',
          icon: const Icon(Icons.swap_vert, color: AppColors.primary),
          onPressed: onSwap,
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

/// The travel day as three one-tap chips -- Today, Tomorrow, and a
/// third that opens the calendar and then shows the day picked -- instead
/// of a row that always opened the calendar: nearly every trip is today or
/// tomorrow, so the common choice costs one tap, not three (Hick, Fitts).
class _DayChips extends StatelessWidget {
  const _DayChips({required this.selected, required this.onSelected, required this.onPick});

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final day = DateUtils.dateOnly(selected);
    final other = day != today && day != tomorrow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            ChoiceChip(
              label: const Text('Today'),
              selected: day == today,
              showCheckmark: false,
              onSelected: (_) => onSelected(today),
            ),
            ChoiceChip(
              label: const Text('Tomorrow'),
              selected: day == tomorrow,
              showCheckmark: false,
              onSelected: (_) => onSelected(tomorrow),
            ),
            ChoiceChip(
              avatar: Icon(Icons.event, size: 16, color: other ? AppColors.onFill : AppColors.primary),
              label: Text(other ? dayShort(day) : 'Other day'),
              selected: other,
              showCheckmark: false,
              tooltip: 'Opens the calendar',
              onSelected: (_) => onPick(),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
