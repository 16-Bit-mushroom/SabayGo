import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/schedule_repository.dart';

/// **Post the timetable for 7 days** (Terminal Manager, on Trips' post
/// box): makes bookable trips from every
/// regular departure in use, starting today, for the days chosen. Trips
/// that already exist are left alone.
///
/// It sat in Setup → Timetable as "Create upcoming trips" until 10 Nov,
/// beside the one-time set-up, though it is needed every few days and
/// nothing runs it on its own: if nobody presses it, passengers find no
/// trips to book. It is daily work, so it lives on Trips. Returns whether
/// any trip was created.
Future<bool> addUpcomingTrips(BuildContext context) async {
  final schedule = context.read<ScheduleRepository>();
  final days = await showDialog<int>(context: context, builder: (_) => const _DaysDialog());
  if (days == null || !context.mounted) return false;
  final List<GenerationReport> reports;
  try {
    reports = await schedule.generateTrips(daysAhead: days);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
  if (!context.mounted) return false;
  final created = reports.fold<int>(0, (n, r) => n + r.tripsCreated);
  final skipped = reports.fold<int>(0, (n, r) => n + r.tripsSkipped);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Trips posted from the schedules'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${created == 1 ? '1 new trip' : '$created new trips'} posted. '
              '${skipped == 1 ? '1 already existed' : '$skipped already existed'} and '
              '${skipped == 1 ? 'was left as it was' : 'were left as they were'}. Passengers can book them now.'),
          for (final r in reports)
            if (r.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('${DateFormat('EEE d MMM yyyy').format(r.serviceDate)}:',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final w in r.warnings) Text('• $w', style: TextStyle(color: AppColors.warning, fontSize: 12.5)),
            ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close'))],
    ),
  );
  return created > 0;
}

class _DaysDialog extends StatefulWidget {
  const _DaysDialog();

  @override
  State<_DaysDialog> createState() => _DaysDialogState();
}

class _DaysDialogState extends State<_DaysDialog> {
  // A week by default: nothing adds trips on its own, so a single day runs
  // out tomorrow.
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Post trips from the schedules'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Makes bookable trips from every trip schedule in use, starting today. '
              'Trips that already exist are left alone.', style: text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(children: [
            Expanded(child: Text('How many days', style: text.bodyMedium)),
            IconButton(
              tooltip: 'One day fewer',
              onPressed: _days > 1 ? () => setState(() => _days--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 32,
              child: Text('$_days', textAlign: TextAlign.center, style: text.titleMedium),
            ),
            IconButton(
              tooltip: 'One day more',
              onPressed: _days < 30 ? () => setState(() => _days++) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
          Text(_days == 1 ? 'Today only.' : 'Today and the next ${_days - 1} days.',
              style: text.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_days), child: const Text('Post trips')),
      ],
    );
  }
}
