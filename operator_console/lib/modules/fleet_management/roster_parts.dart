import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';

/// Words, badges and the validation panel shared by Setup's Operators &
/// vans and Staff steps (brief 3, Member Records).
///
/// **What validation is.** Only the records that can be put on a trip are
/// validated: operators, vans and Dispatchers. Only validated ones can be
/// assigned. Cashiers and Terminal Managers sign in at the desk and are
/// never assigned to a van, so they have none. The brief's rules, all the
/// server's: a van needs its four photos, nobody validates a record they
/// imported, and a changed record or photo goes back to Pending. What A2Z
/// checks on paper before validating is A2Z's to say
/// (`docs/QUESTIONS_FOR_COOPERATIVE.md`), so the panel shows the record's
/// facts, never an invented checklist.
class Roster {
  static const validationRule =
      'Only validated operators, vans and Dispatchers can be assigned to a trip. A van needs its four '
      'photos first, nobody validates a record they imported, and a changed record goes back to Pending.';

  static const officeNoValidation =
      'Office accounts sign in at the desk and are never assigned to a van, so they are not validated. '
      'A2Z validates operators, vans and Dispatchers only.';

  static String validationWord(String s) => switch (s) {
        'validated' => 'Validated',
        'rejected' => 'Rejected',
        'suspended' => 'Suspended',
        _ => 'Pending',
      };

  static Widget validationBadge(String s) => StatusBadge(
        validationWord(s),
        tone: switch (s) {
          'validated' => Tone.success,
          'rejected' => Tone.danger,
          'suspended' => Tone.neutral,
          _ => Tone.warning,
        },
      );

  /// Role in words. Never "operator" for staff: under LTFRB usage that is
  /// the franchise holder, here the van owner, who has no account.
  static String roleLabel(String role) => switch (role) {
        'dispatcher' => 'Dispatcher',
        'terminal_manager' => 'Terminal Manager',
        'cashier' => 'Cashier',
        'admin' => 'Administrator',
        _ => role,
      };

  /// Van and crew states in the office's words. The stored values
  /// (`maintenance`, `inactive`) are the system's.
  static String vanStatus(String s) => switch (s) {
        'active' => 'In service',
        'maintenance' => 'Under repair',
        'inactive' => 'Not in use',
        _ => s,
      };

  static String crewStatus(String s) => switch (s) {
        'active' => 'Working',
        'suspended' => 'Suspended',
        'inactive' => 'No longer working',
        _ => s,
      };

  /// Three states, three tones, each with its word on the chip: in service,
  /// temporarily out (maintenance, suspended), and retired.
  static Widget statusBadge(String status, String label) => StatusBadge(
        label,
        tone: switch (status) {
          'active' => Tone.success,
          'maintenance' || 'suspended' => Tone.warning,
          _ => Tone.neutral,
        },
      );

  /// As every other date on the console: "3 Mar 2027".
  static String day(DateTime d) => DateFormat('d MMM yyyy').format(d);
}

/// One fact a validator looks at, with its mark: met, a gap that blocks
/// Validate, or a note to read.
class RecordCheck {
  const RecordCheck(this.text, {this.met = true, this.blocks = false});
  final String text;
  final bool met;

  /// The server refuses Validate while this is unmet.
  final bool blocks;
}

/// The record's validation, decided in place: its state, what it carries,
/// and the Terminal Manager's buttons. Validate is disabled, with the
/// reason on screen, while a blocking check is unmet; the server stays the
/// authority and a refusal comes back in its own words.
class ValidationPanel extends StatelessWidget {
  const ValidationPanel({
    super.key,
    required this.status,
    required this.checks,
    required this.canDecide,
    required this.onDecide,
  });

  final String status;
  final List<RecordCheck> checks;
  final bool canDecide;
  final ValueChanged<String> onDecide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final blocked = checks.any((c) => c.blocks && !c.met);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Validation', style: text.titleSmall),
        const SizedBox(width: AppSpacing.sm),
        Roster.validationBadge(status),
      ]),
      const SizedBox(height: AppSpacing.sm),
      for (final c in checks)
        FactLine(
          c.met ? Icons.check_circle_outline : (c.blocks ? Icons.lock_outline : Icons.info_outline),
          c.text,
          colour: c.met ? null : (c.blocks ? AppColors.warning : null),
        ),
      const SizedBox(height: AppSpacing.xs),
      Text(Roster.validationRule, style: text.bodySmall),
      if (canDecide) ...[
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          if (status != 'validated')
            FilledButton(onPressed: blocked ? null : () => onDecide('validated'), child: const Text('Validate')),
          // Both take the record off trips at once, so a misclick asks
          // first; "Back to pending" undoes either.
          if (status != 'rejected')
            OutlinedButton(
              onPressed: () async {
                if (await askConfirm(context,
                    title: 'Reject this record?',
                    body: 'It cannot be assigned to a trip while rejected. "Back to pending" undoes this.',
                    confirmLabel: 'Reject')) {
                  onDecide('rejected');
                }
              },
              child: const Text('Reject'),
            ),
          if (status != 'suspended' && status == 'validated')
            OutlinedButton(
              onPressed: () async {
                if (await askConfirm(context,
                    title: 'Suspend this record?',
                    body: 'It cannot be assigned to a trip while suspended. "Back to pending" undoes this.',
                    confirmLabel: 'Suspend')) {
                  onDecide('suspended');
                }
              },
              child: const Text('Suspend'),
            ),
          if (status != 'pending')
            TextButton(onPressed: () => onDecide('pending'), child: const Text('Back to pending')),
        ]),
      ],
    ]);
  }
}

/// A record's working status, changed in place. A dropdown: the office's
/// words ("No longer working") do not fit three segments in a side panel.
class StatusPicker extends StatelessWidget {
  const StatusPicker({
    super.key,
    required this.value,
    required this.options,
    required this.word,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final String Function(String) word;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // Keyed by the value, so a refused change snaps back to the stored one.
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Status'),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(word(o)))],
      onChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
    );
  }
}
