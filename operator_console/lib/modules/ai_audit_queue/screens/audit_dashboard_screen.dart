import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/design/components/components.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/audit_repository.dart';
import '../audit_reading_card.dart';
import '../../../core/design/tokens.dart';

class AuditDashboardScreen extends StatefulWidget {
  const AuditDashboardScreen({super.key});

  @override
  State<AuditDashboardScreen> createState() => _AuditDashboardScreenState();
}

class _AuditDashboardScreenState extends State<AuditDashboardScreen> {
  late final AuditRepository _audits = context.read<AuditRepository>();

  List<PendingAudit>? _logs;
  int _selectedIndex = 0;
  /// G.2: false = the open queue, true = everything that has left it.
  bool _showHistory = false;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  final _rowsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    // The screen is kept alive by the shell's IndexedStack -- initState
    // only runs once, so without a poll a variance that lands after that
    // (including one the notification bell "jumps" you here for) never
    // appears until a manual refresh. Mirrors the bell's own 30s poll.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_loading) _load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _rowsScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = _showHistory ? await _audits.history() : await _audits.pending();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        if (_selectedIndex >= logs.length) _selectedIndex = 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(PendingAudit audit, {required String resolution}) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _ResolveNotesDialog(
        title: resolution == 'resolved' ? 'Confirm a problem' : 'Close this check',
        prompt: resolution == 'resolved'
            ? 'What did you find? For example: two walk-ins the conductor did not log.'
            : 'Why is no action needed? For example: one passenger was out of the photo.',
      ),
    );
    if (notes == null || notes.trim().isEmpty) return;

    try {
      await _audits.resolve(auditId: audit.auditId, resolution: resolution, notes: notes.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resolution == 'resolved'
              ? 'Saved as a confirmed problem.'
              : 'Check closed -- no action needed.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final logs = _logs ?? [];
        final selectedLog = logs.isNotEmpty ? logs[_selectedIndex] : null;

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Passenger Count Checks',
                technicalNote: 'YOLOv8 camera',
                description: 'The camera counts the people in a van and compares the number '
                    'with the passenger list. Review the checks that do not match.',
                actions: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false, label: Text('Needs review'), icon: Icon(Icons.pending_actions)),
                      ButtonSegment(value: true, label: Text('History'), icon: Icon(Icons.history)),
                    ],
                    selected: {_showHistory},
                    showSelectedIcon: false,
                    onSelectionChanged: _loading
                        ? null
                        : (sel) {
                            setState(() {
                              _showHistory = sel.first;
                              _selectedIndex = 0;
                            });
                            _load();
                          },
                  ),
                  RefreshButton(onPressed: _load, busy: _loading),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? LoadError(message: _error!, onRetry: _load)
                        : logs.isEmpty
                            ? _buildEmpty()
                            : isDesktop
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 3, child: _buildDataGrid(logs)),
                                      const SizedBox(width: 24),
                                      Expanded(flex: 2, child: _buildProofPanel(selectedLog!)),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        _buildDataGrid(logs),
                                        const SizedBox(height: 24),
                                        _buildProofPanel(selectedLog!),
                                      ],
                                    ),
                                  ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() => _showHistory
      ? const EmptyState(
          icon: Icons.history,
          title: 'No checks closed yet',
          hint: 'Checks you close, and checks that matched, are listed here.',
        )
      : const EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Nothing to review',
          hint: 'Every camera count so far matches its passenger list.',
        );

  /// The audit list: full width, headings pinned, one row selected.
  ///
  /// Not a [DataTable], for two reasons. A DataTable is only as wide as its
  /// columns, so its heading strip stopped at "Variance" while the card
  /// ran on -- the half-filled header in the screenshot. And selecting a
  /// row gave every row a checkbox plus a select-all box in the header,
  /// which promises multi-select on a list where exactly one audit is open
  /// in the panel at a time. Selection is now a click on the row, shown by
  /// a tinted fill, bold text and an ink bar at the left edge -- three
  /// cues, so it never rests on colour alone.
  Widget _buildDataGrid(List<PendingAudit> logs) {
    final columns = <(String, int, bool)>[
      ('Trip', 22, false),
      ('Section', 9, true),
      ('Passenger list', 14, true),
      ('Camera count', 14, true),
      ('Difference', 12, true),
      if (_showHistory) ('Outcome', 18, false),
      if (_showHistory) ('Closed', 16, false),
    ];
    final minWidth = _showHistory ? 720.0 : 520.0;

    Widget cell(int i, Widget child) {
      final (_, flex, numeric) = columns[i];
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Align(
            alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      );
    }

    const figures = TextStyle(
      color: AppColors.textPrimary,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget heading() => Container(
          height: 44,
          color: AppColors.surfaceSunken,
          padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.xs),
          child: Row(children: [
            for (var i = 0; i < columns.length; i++)
              cell(
                i,
                Text(columns[i].$1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              ),
          ]),
        );

    Widget row(int index) {
      final log = logs[index];
      final selected = _selectedIndex == index;
      final alert = log.variance > 0;
      final alertStyle = figures.copyWith(
        color: alert ? AppColors.danger : AppColors.textPrimary,
        fontWeight: alert ? FontWeight.w700 : FontWeight.normal,
      );
      // A negative variance used to render as "+-1".
      final variance = log.variance > 0 ? '+${log.variance}' : '${log.variance}';

      return Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.primaryContainer : AppColors.surfaceRaised,
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            hoverColor: AppColors.surfaceSunken,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: selected ? AppColors.primary : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Row(children: [
                cell(
                  0,
                  Text(log.tripLabel ?? log.tripId.substring(0, 8),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      )),
                ),
                cell(1, Text('${log.legSequence}', style: figures)),
                cell(2, Text('${log.bookedCount}', style: figures)),
                cell(3, Text('${log.visualCount}', style: alertStyle)),
                cell(4, Text(variance, style: alertStyle)),
                if (_showHistory) cell(5, auditOutcomeBadge(log.resolutionStatus)),
                if (_showHistory)
                  cell(
                    6,
                    Text(
                      log.resolvedAt == null ? '—' : DateFormat.jm().add_MMMd().format(log.resolvedAt!),
                      overflow: TextOverflow.ellipsis,
                      style: figures,
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
        // Beside the proof panel the height is bounded: the card shrinks to
        // its rows and scrolls once they outgrow it. Stacked on a narrow
        // screen it sits in the page's own scroll view, so it lays every
        // row out instead -- a flexible list there has no height to fill.
        final body = c.hasBoundedHeight
            ? Flexible(
                child: Scrollbar(
                  controller: _rowsScroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _rowsScroll,
                    shrinkWrap: true,
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => row(i),
                  ),
                ),
              )
            : Column(children: [
                for (var i = 0; i < logs.length; i++) ...[
                  if (i > 0) const Divider(),
                  row(i),
                ],
              ]);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: width,
              maxWidth: width,
              maxHeight: c.maxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [heading(), const Divider(), body],
            ),
          ),
        );
      }),
    );
  }


  Widget _buildProofPanel(PendingAudit log) {
    final isAlert = log.variance > 0;
    final imageUrl = log.snapshotAbsoluteUrl;
    return Panel(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Check on ${log.tripLabel ?? log.tripId.substring(0, 8)}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  auditOutcomeBadge(log.resolutionStatus),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: imageUrl == null
                    ? const Center(
                        child: Icon(Icons.image_not_supported_outlined, color: AppColors.border, size: 40))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined, color: AppColors.border, size: 40)),
                          loadingBuilder: (context, child, progress) => progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              // Numbers alone do not say whether a +2 is a problem or a -4
              // is harmless; the reading does.
              AuditReadingCard(audit: log),
              const SizedBox(height: 24),
              Text('DETAILS', style: Theme.of(context).textTheme.labelSmall),
              const Divider(),
              _buildDetailRow('Photo taken', DateFormat.jm().add_yMMMd().format(log.capturedAt)),
              _buildDetailRow('How it started', log.triggerLabel),
              _buildDetailRow('Section of the route', '${log.legSequence}'),
              _buildDetailRow('On the passenger list', log.bookedCount.toString()),
              _buildDetailRow('Camera counted', log.visualCount.toString(), isAlert: isAlert),
              // Signed, and not called "leakage": a shortfall is a camera-view
              // question, never missing money. It used to print "+-4".
              _buildDetailRow(
                'Difference (camera − list)',
                log.variance == 0
                    ? 'None'
                    : '${log.variance > 0 ? '+' : '−'}${log.variance.abs()} '
                        '${log.variance.abs() == 1 ? 'person' : 'people'}',
                isAlert: log.variance > 0,
              ),
              if (log.confidenceAvg != null)
                _buildDetailRow('Camera confidence', '${(log.confidenceAvg! * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 32),
              if (!log.isPending) ...[
                // G.2: a closed audit shows its disposition instead of the buttons.
                _buildDetailRow('Closed by', log.resolvedBy ?? '—'),
                _buildDetailRow(
                  'Closed at',
                  log.resolvedAt == null ? '—' : DateFormat.jm().add_yMMMd().format(log.resolvedAt!),
                ),
                if ((log.resolutionNotes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Notes', style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Text(log.resolutionNotes!, style: const TextStyle(color: AppColors.textPrimary, height: 1.4)),
                ],
              ] else if (isAlert)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _resolve(log, resolution: 'resolved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: AppColors.onFill,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        icon: const Icon(Icons.report_outlined),
                        label: const Text('Confirm problem'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _resolve(log, resolution: 'ignored'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Dismiss'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _resolve(log, resolution: 'ignored'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceSunken,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Looks fine — close it'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isAlert ? Theme.of(context).colorScheme.error : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolveNotesDialog extends StatefulWidget {
  const _ResolveNotesDialog({required this.title, required this.prompt});
  final String title;
  final String prompt;

  @override
  State<_ResolveNotesDialog> createState() => _ResolveNotesDialogState();
}

class _ResolveNotesDialogState extends State<_ResolveNotesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Note (required, kept on record)',
            hintText: widget.prompt,
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        // Disabled until there is a note: the record needs one, and a Save
        // that silently does nothing on an empty note looked broken.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, v, _) => FilledButton(
            onPressed: v.text.trim().isEmpty ? null : () => Navigator.of(context).pop(v.text),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
