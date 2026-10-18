import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../network/api_exception.dart';
import '../tokens.dart';

/// Run one call and report it through the app-wide messenger: [done] on
/// success, the server's own sentence on a refusal. True when it worked.
Future<bool> runAction(BuildContext context, Future<void> Function() call, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await call();
    messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.message),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
    ));
    return false;
  }
}

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
  });

  final String title;
  final String intro;
  final String label;
  final String confirmLabel;
  final bool required;
  final bool danger;
  final int maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _text = TextEditingController();

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
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
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
          Text(
            today ? 'Today, ${DateFormat.MMMd().format(day)}' : DateFormat.yMMMEd().format(day),
            style: Theme.of(context).textTheme.titleSmall,
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
