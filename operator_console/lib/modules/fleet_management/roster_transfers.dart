import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../core/util/download.dart';
import '../../core/util/pick_file.dart';
import '../../data/repositories/fleet_repository.dart';

const _xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Import and export of the member roster (brief 8), for the Terminal
/// Manager and the Cashier: the binder copied into a template, every row
/// checked and previewed before anything is saved, and any list exported
/// as CSV or PDF. Every import and export is logged.
class RosterTransfers extends StatelessWidget {
  const RosterTransfers({super.key, required this.onImported});
  final VoidCallback onImported;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PopupMenuButton<String>(
        tooltip: 'Import from the binder',
        onSelected: (type) async {
          final saved = await showDialog<bool>(context: context, builder: (_) => _ImportDialog(recordType: type));
          if (saved == true) onImported();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'operators', child: Text('Import operators')),
          PopupMenuItem(value: 'vans', child: Text('Import vans')),
        ],
        child: const _MenuLabel(Icons.upload_file, 'Import'),
      ),
      const SizedBox(width: AppSpacing.sm),
      PopupMenuButton<(String, String, String)>(
        tooltip: 'Export a list',
        onSelected: (pick) => _export(context, pick.$1, pick.$2, pick.$3),
        itemBuilder: (_) => const [
          PopupMenuItem(value: ('operators', 'csv', 'backup'), child: Text('Operators · CSV')),
          PopupMenuItem(value: ('operators', 'pdf', 'backup'), child: Text('Operators · PDF')),
          PopupMenuItem(value: ('vans', 'csv', 'backup'), child: Text('Vans · CSV')),
          PopupMenuItem(value: ('vans', 'pdf', 'backup'), child: Text('Vans · PDF')),
          PopupMenuItem(value: ('vans', 'pdf', 'ltfrb_check'), child: Text('Vans · LTFRB cross-check list (PDF)')),
          PopupMenuItem(value: ('dispatchers', 'csv', 'backup'), child: Text('Dispatchers · CSV')),
          PopupMenuItem(value: ('dispatchers', 'pdf', 'backup'), child: Text('Dispatchers · PDF')),
        ],
        child: const _MenuLabel(Icons.download, 'Export'),
      ),
      IconButton(
        tooltip: 'Imports and exports so far',
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _TransferLog()),
        icon: Icon(Icons.history, color: AppColors.textMuted),
      ),
    ]);
  }

  static Future<void> _export(BuildContext context, String type, String format, String purpose) async {
    final fleet = context.read<FleetRepository>();
    await runAction(context, () async {
      final bytes = await fleet.export(type, format: format, purpose: purpose);
      downloadBytes(bytes,
          filename: 'sabaygo_${type}_${purpose}_${DateFormat('yyyyMMdd').format(DateTime.now())}.$format',
          mimeType: format == 'pdf' ? 'application/pdf' : 'text/csv');
    }, 'Export downloaded and logged.');
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(label),
          Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
        ]),
      );
}

/// Template, file, preview with the reason for each failing row, then
/// save. The file is sent again on save and re-checked; passing rows are
/// saved Pending under one batch, failing rows can be downloaded with
/// their reasons, corrected and uploaded again.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.recordType});
  final String recordType;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final FleetRepository _fleet = context.read<FleetRepository>();
  PickedFile? _file;
  ImportResult? _preview;
  ImportResult? _saved;
  bool _busy = false;
  String? _error;

  String get _noun => widget.recordType == 'vans' ? 'vans' : 'operators';

  Future<void> _template(String format) async {
    try {
      final bytes = await _fleet.template(widget.recordType, format);
      downloadBytes(bytes,
          filename: 'sabaygo_${widget.recordType}_template.$format',
          mimeType: format == 'csv' ? 'text/csv' : _xlsx);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _choose() async {
    final file = await pickFile(accept: '.csv,.xlsx');
    if (file == null) return;
    setState(() {
      _file = file;
      _preview = null;
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _fleet.previewImport(widget.recordType, file.bytes, file.name);
      if (mounted) setState(() => _preview = preview);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final file = _file!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _fleet.confirmImport(widget.recordType, file.bytes, file.name);
      if (mounted) setState(() => _saved = saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejected() async {
    try {
      final bytes = await _fleet.rejectedRows(_saved!.transferId!);
      downloadBytes(bytes, filename: 'sabaygo_${widget.recordType}_rejected.csv', mimeType: 'text/csv');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _preview;
    final saved = _saved;
    return AlertDialog(
      title: Text('Import $_noun'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (saved == null) ...[
            Text('1. Copy the binder into the template. ${widget.recordType == 'vans' ? 'Photographs are '
                'uploaded afterwards, one van at a time.' : ''}'),
            Wrap(spacing: AppSpacing.sm, children: [
              TextButton(onPressed: () => _template('xlsx'), child: const Text('Excel template')),
              TextButton(onPressed: () => _template('csv'), child: const Text('CSV template')),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              const Text('2. '),
              OutlinedButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(_file == null ? 'Choose the filled-in file' : _file!.name),
              ),
            ]),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
            ),
          if (preview != null && saved == null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('3. Check: ${preview.passing} rows pass, ${preview.failing} fail. Only passing rows are saved.',
                style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(shrinkWrap: true, children: [
                for (final r in preview.rows)
                  ListTile(
                    dense: true,
                    leading: Icon(r.ok ? Icons.check_circle_outline : Icons.error_outline,
                        color: r.ok ? AppColors.success : AppColors.danger),
                    title: Text('Row ${r.row}: ${r.values.values.where((v) => v != null && '$v'.isNotEmpty).take(3).join(' · ')}'),
                    subtitle: r.ok ? null : Text(r.errors.join('; ')),
                  ),
              ]),
            ),
          ],
          if (saved != null) ...[
            Text('${saved.passing} $_noun saved, Pending until the Terminal Manager validates them.',
                style: text.titleSmall),
            if (saved.failing > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('${saved.failing} rows were not saved. Download them with the reason for each, '
                  'correct them and import that file again.'),
              TextButton.icon(
                onPressed: saved.transferId == null ? null : _rejected,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download rejected rows'),
              ),
            ],
          ],
        ]),
      ),
      actions: saved != null
          ? [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done'))]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: !_busy && preview != null && preview.passing > 0 ? _save : null,
                child: Text('Save ${preview?.passing ?? 0} rows'),
              ),
            ],
    );
  }
}

class _TransferLog extends StatelessWidget {
  const _TransferLog();

  static final _when = DateFormat('d MMM yyyy, h:mm a');

  @override
  Widget build(BuildContext context) {
    final fleet = context.read<FleetRepository>();
    return AlertDialog(
      title: const Text('Imports and exports'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: FutureBuilder(
          future: fleet.transfers(),
          builder: (_, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return Text(e is ApiException ? e.message : '$e');
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('Nothing imported or exported yet.'));
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = rows[i];
                return ListTile(
                  leading: Icon(t.direction == 'import' ? Icons.upload_file : Icons.download),
                  title: Text('${t.direction == 'import' ? 'Imported' : 'Exported'} ${t.recordType}: ${t.fileName}'),
                  subtitle: Text('${t.byName ?? '—'}, ${_when.format(t.at)} · ${t.rowsAccepted} rows'
                      '${t.rowsRejected > 0 ? ', ${t.rowsRejected} rejected' : ''}'),
                  trailing: t.hasRejected
                      ? IconButton(
                          tooltip: 'Download rejected rows',
                          icon: const Icon(Icons.download),
                          onPressed: () => runAction(context, () async {
                            downloadBytes(await fleet.rejectedRows(t.transferId),
                                filename: 'sabaygo_${t.recordType}_rejected.csv', mimeType: 'text/csv');
                          }, 'Rejected rows downloaded.'),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
