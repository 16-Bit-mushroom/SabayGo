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

  // From and To in their own tinted boxes, the swap button on the line
  // between them at the right (20 Nov redesign). The boxes keep a lane free
  // for the button, so it never covers a name.
  Widget _form(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Column(
                  children: [
                    _TerminalBox(
                      child: TerminalPickerField(
                        end: JourneyEnd.boarding,
                        label: 'From',
                        sheetTitle: 'Where are you boarding?',
                        value: vm.selectedOrigin,
                        nodes: vm.nodes,
                        onChanged: vm.setOrigin,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TerminalBox(
                      child: TerminalPickerField(
                        end: JourneyEnd.alighting,
                        label: 'To',
                        sheetTitle: 'Where are you going?',
                        value: vm.selectedDestination,
                        nodes: vm.nodes,
                        onChanged: vm.setDestination,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: AppSpacing.xs,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _SwapButton(onSwap: vm.swapNodes)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // One field that opens the calendar (20 Nov, the owner), in place
            // of the Today / Tomorrow / Other day buttons.
            _TerminalBox(
              lane: false,
              child: AppPickerRow(
                leading: const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                label: 'Day',
                value: dayFriendly(vm.serviceDate),
                placeholder: 'Choose a day',
                semanticHint: 'Opens the calendar',
                onTap: () => _pickDate(context),
              ),
            ),
          ],
        ),
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

/// One terminal question in a tinted box. The right edge leaves a lane
/// for the swap button.
class _TerminalBox extends StatelessWidget {
  const _TerminalBox({required this.child, this.lane = true});

  final Widget child;

  /// Keep the swap button's lane free beside the text. Off for the Day
  /// box, which has no button beside it.
  final bool lane;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.only(right: lane ? _SwapButton.lane : 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// Exchanges From and To. Round, on the line between the two boxes: its
/// place says what it does, and the tooltip and label say it too.
class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onSwap});

  final VoidCallback onSwap;

  /// The width kept free beside the terminal names.
  static const double lane = 52;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: 'Swap From and To',
        onPressed: onSwap,
        icon: const Icon(Icons.swap_vert),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceRaised,
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          minimumSize: const Size(AppSizing.minTouchTarget, AppSizing.minTouchTarget),
        ),
      );
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
