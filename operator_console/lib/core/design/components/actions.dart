import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../network/api_exception.dart';
import '../tokens.dart';

/// Ticks after any action that changed something on the server, so the
/// figures other parts of the page show -- the top bar, the review counts
/// -- reload at once instead of on their next 30 s round (12 Nov UI run:
/// "No open emergencies" under a top bar still saying 1).
final consoleChanged = ValueNotifier<int>(0);

void announceChange() => consoleChanged.value++;

/// Run one call and report it through the app-wide messenger: [done] on
/// success, the server's own sentence on a refusal. True when it worked.
///
/// One at a time: a second click while a call is still out (a double click
/// on Validate, Start, Record payment) is dropped, not sent twice.
Future<bool> runAction(BuildContext context, Future<void> Function() call, String done) async {
  if (_actionRunning) return false;
  _actionRunning = true;
  final messenger = ScaffoldMessenger.of(context);
  void refused(String message) => messenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
  try {
    await call();
    messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
    announceChange();
    return true;
  } on ApiException catch (e) {
    refused(e.message);
    return false;
  } catch (_) {
    // The request may have gone through before the reply failed to read:
    // say so, rather than claim it failed.
    refused('That did not finish cleanly. Refresh to see whether it was saved.');
    return false;
  } finally {
    _actionRunning = false;
  }
}

bool _actionRunning = false;

/// Asks before a step that takes someone or something out of service.
/// True only when [confirmLabel] was pressed.
Future<bool> askConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 440, child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    ) ==
    true;

/// A dialog that asks for a sentence: a reason, a note, the operator's
/// words. Null when cancelled; '' when the text is optional and left empty.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String intro,
  required String label,
  required String confirmLabel,
  bool required = true,
  bool danger = false,
  int maxLength = 255,
  String initial = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: title,
        intro: intro,
        label: label,
        confirmLabel: confirmLabel,
        required: required,
        danger: danger,
        maxLength: maxLength,
        initial: initial,
      ),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.intro,
    required this.label,
    required this.confirmLabel,
    required this.required,
    required this.danger,
    required this.maxLength,
    this.initial = '',
  });

  final String title;
  final String intro;
  final String label;
  final String confirmLabel;
  final bool required;
  final bool danger;
  final int maxLength;
  /// Text the field starts with, such as a suggested amount.
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ok => !widget.required || _text.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.intro),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _text,
              autofocus: true,
              maxLength: widget.maxLength,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.required ? widget.label : '${widget.label} (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ok ? () => Navigator.pop(context, _text.text.trim()) : null,
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.onFill) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// The day a page shows, a day back or forward at a time.
class DayPicker extends StatelessWidget {
  const DayPicker({super.key, required this.day, required this.onShift});
  final DateTime day;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, DateTime.now());
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => onShift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          // The day itself opens a calendar, so a day weeks away is one
          // pick rather than many presses of an arrow. The choice reaches
          // the page as a shift, so every page that uses this gets it.
          Tooltip(
            message: 'Choose a day',
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
              onPressed: () async {
                final from = DateUtils.dateOnly(day);
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: from,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 1, 12, 31),
                  helpText: 'Choose a day',
                  confirmText: 'Show this day',
                );
                if (picked == null) return;
                final shift = DateUtils.dateOnly(picked).difference(from).inDays;
                if (shift != 0) onShift(shift);
              },
              icon: const Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.primary),
              label: Text(
                today ? 'Today, ${DateFormat.MMMd().format(day)}' : DateFormat.yMMMEd().format(day),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => onShift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Pesos as the office writes them.
final peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

/// A day as the server takes it in a query.
String isoDay(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

/// One line of fact with its icon, in a colour when it needs attention.
class FactLine extends StatelessWidget {
  const FactLine(this.icon, this.text, {super.key, this.colour});
  final IconData icon;
  final String text;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour ?? AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colour)),
          ),
        ],
      ),
    );
  }
}
