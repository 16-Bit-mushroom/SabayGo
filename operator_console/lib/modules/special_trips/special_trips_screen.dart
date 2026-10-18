import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/rental_repository.dart';
import '../trip_monitor/trip_lifecycle_panel.dart';

/// Special Trips (brief 2.5, 9): renting the whole van. Requests come from
/// the passenger's app, or the Terminal Manager or the Cashier enters one
/// for a customer at the counter. The office agrees the fee by pickup and
/// destination, with a note of what it is based on -- approving creates
/// the trip -- or refuses with a reason the passenger is told. The trip is
/// then assigned, paid and started like any other (the Trips page's Start
/// and departure panel, shown here beside the request).
class SpecialTripsScreen extends StatefulWidget {
  const SpecialTripsScreen({super.key});

  @override
  State<SpecialTripsScreen> createState() => _SpecialTripsScreenState();
}

class _SpecialTripsScreenState extends State<SpecialTripsScreen> {
  late final RentalRepository _rentals = context.read<RentalRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  String _view = 'requested';
  List<RentalRequest>? _list;
  String? _selected;
  TripBoardEntry? _trip;
  bool _loading = true;
  String? _error;

  static final _when = DateFormat('EEE d MMM, h:mm a');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _rentals.list();
      final list = [
        for (final r in all)
          if (_view == 'closed' ? !const {'requested', 'approved'}.contains(r.status) : r.status == _view) r
      ];
      if (!mounted) return;
      setState(() {
        _list = list;
        if (!list.any((r) => r.requestId == _selected)) _selected = list.firstOrNull?.requestId;
      });
      await _loadTrip();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The approved request's trip, from the day's trip board, for its Start
  /// and departure panel.
  Future<void> _loadTrip() async {
    final r = _list?.where((x) => x.requestId == _selected).firstOrNull;
    if (r?.tripId == null) {
      if (mounted) setState(() => _trip = null);
      return;
    }
    try {
      final board = await _dispatch.tripBoard(DateUtils.dateOnly(r!.pickupAt));
      if (mounted) setState(() => _trip = board.where((t) => t.tripId == r.tripId).firstOrNull);
    } on ApiException {
      if (mounted) setState(() => _trip = null);
    }
  }

  Future<void> _walkIn() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _WalkInDialog());
    if (ok == true) {
      setState(() => _view = 'approved');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list ?? const <RentalRequest>[];
    final selected = list.where((r) => r.requestId == _selected).firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(
          title: 'Special Trips',
          technicalNote: 'Special_Trip_Requests',
          description: 'Requests to rent the whole van. Agree the fee by pickup and destination, then '
              'assign a van and a Dispatcher. The fee is paid before the van leaves.',
          actions: [
            FilledButton.icon(
              onPressed: _walkIn,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Walk-in request'),
            ),
            RefreshButton(onPressed: _load, busy: _loading),
          ],
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'requested', label: Text('Waiting')),
            ButtonSegment(value: 'approved', label: Text('Approved')),
            ButtonSegment(value: 'closed', label: Text('Closed')),
          ],
          selected: {_view},
          onSelectionChanged: (s) {
            setState(() {
              _view = s.first;
              _selected = null;
            });
            _load();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _loading && _list == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? LoadError(message: _error!, onRetry: _load)
                  : list.isEmpty
                      ? const EmptyState(icon: Icons.airport_shuttle_outlined, title: 'No requests here')
                      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 400,
                            child: Panel(
                              fill: true,
                              padding: EdgeInsets.zero,
                              child: ListView(children: [
                                for (final r in list)
                                  ListTile(
                                    selected: r.requestId == _selected,
                                    onTap: () {
                                      setState(() => _selected = r.requestId);
                                      _loadTrip();
                                    },
                                    title: Text(_when.format(r.pickupAt)),
                                    subtitle: Text('${r.customerName ?? 'App passenger'} · ${r.passengerCount} pax\n'
                                        '${r.pickupAddress} → ${r.destinationAddress}'),
                                    isThreeLine: true,
                                    trailing: _badge(r),
                                  ),
                              ]),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: selected == null
                                ? const SizedBox.shrink()
                                : ListView(children: [
                                    _RequestPanel(request: selected, onChanged: _load),
                                    if (_trip case final trip?) ...[
                                      const SizedBox(height: AppSpacing.lg),
                                      TripLifecyclePanel(trip: trip, onChanged: _load),
                                    ],
                                  ]),
                          ),
                        ]),
        ),
      ]),
    );
  }

  static Widget _badge(RentalRequest r) => switch (r.status) {
        'requested' => const StatusBadge('Waiting', tone: Tone.warning),
        'approved' => r.paymentStatus == 'paid'
            ? const StatusBadge('Fee paid', tone: Tone.success)
            : const StatusBadge('Fee unpaid', tone: Tone.info),
        'rejected' => const StatusBadge('Refused', tone: Tone.danger),
        'completed' => const StatusBadge('Done'),
        _ => const StatusBadge('Withdrawn'),
      };
}

class _RequestPanel extends StatelessWidget {
  const _RequestPanel({required this.request, required this.onChanged});
  final RentalRequest request;
  final VoidCallback onChanged;

  static final _when = DateFormat('EEEE d MMMM yyyy, h:mm a');

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Panel(
      title: _when.format(r.pickupAt),
      icon: Icons.airport_shuttle_outlined,
      trailing: _SpecialTripsScreenState._badge(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FactLine(Icons.person_outline, r.fromApp
            ? 'Requested in the app'
            : 'Walk-in: ${r.customerName ?? '—'}, ${r.customerContact ?? '—'}'),
        FactLine(Icons.place_outlined, '${r.pickupAddress} → ${r.destinationAddress}'),
        FactLine(Icons.groups_outlined, '${r.passengerCount} passengers (the van seats 14)'),
        if (r.fee != null)
          FactLine(Icons.payments_outlined, 'Fee ${peso.format(r.fee)}${r.feeNote != null ? ': ${r.feeNote}' : ''}'
              ' · ${r.paymentStatus == 'paid' ? 'paid' : 'not paid yet: Start waits for it'}'),
        if (r.status == 'approved' && r.tripId != null)
          const FactLine(Icons.info_outline, 'Assign a van and a Dispatcher below. The operator may decline '
              'one that is too far; assign another van then.'),
        if (r.status == 'requested') ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            FilledButton.icon(
              onPressed: () => _approve(context),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Agree the fee'),
            ),
            OutlinedButton(
              onPressed: () => _reject(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Refuse'),
            ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final rentals = context.read<RentalRepository>();
    final picked = await showDialog<(String, String)>(context: context, builder: (_) => const _FeeDialog());
    if (picked == null || !context.mounted) return;
    if (await runAction(context, () => rentals.approve(request.requestId, fee: picked.$1, feeNote: picked.$2),
        'Fee agreed. The trip is created; assign its van and Dispatcher.')) {
      onChanged();
    }
  }

  Future<void> _reject(BuildContext context) async {
    final rentals = context.read<RentalRepository>();
    final reason = await askText(context,
        title: 'Refuse the request',
        intro: 'The passenger is told, with your reason.',
        label: 'Reason',
        confirmLabel: 'Refuse',
        danger: true);
    if (reason == null || !context.mounted) return;
    if (await runAction(context, () => rentals.reject(request.requestId, reason), 'Request refused.')) {
      onChanged();
    }
  }
}

/// The agreed fee and what it is based on.
class _FeeFields extends StatelessWidget {
  const _FeeFields({required this.fee, required this.note, required this.onChanged});
  final TextEditingController fee;
  final TextEditingController note;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: fee,
          onChanged: (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rental fee', prefixText: '₱ '),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: note,
          onChanged: (_) => onChanged(),
          maxLength: 255,
          decoration: const InputDecoration(
            labelText: 'What the fee is based on',
            hintText: 'Ecoland to Samal ferry, half day',
          ),
        ),
      ]);
}

bool _feeOk(TextEditingController fee, TextEditingController note) =>
    (double.tryParse(fee.text) ?? 0) > 0 && note.text.trim().length >= 3;

class _FeeDialog extends StatefulWidget {
  const _FeeDialog();

  @override
  State<_FeeDialog> createState() => _FeeDialogState();
}

class _FeeDialogState extends State<_FeeDialog> {
  final _fee = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _fee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Agree the fee'),
        content: SizedBox(
          width: 420,
          child: _FeeFields(fee: _fee, note: _note, onChanged: () => setState(() {})),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _feeOk(_fee, _note)
                ? () => Navigator.pop(context, (double.parse(_fee.text).toStringAsFixed(2), _note.text.trim()))
                : null,
            child: const Text('Agree and create the trip'),
          ),
        ],
      );
}

/// A customer at the counter: the same details as the app's request, and
/// the fee agreed on the spot.
class _WalkInDialog extends StatefulWidget {
  const _WalkInDialog();

  @override
  State<_WalkInDialog> createState() => _WalkInDialogState();
}

class _WalkInDialogState extends State<_WalkInDialog> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  DateTime? _when;
  int _count = 1;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _pickup, _destination, _fee, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ok =>
      _name.text.trim().length >= 2 &&
      _contact.text.trim().length >= 7 &&
      _pickup.text.trim().length >= 3 &&
      _destination.text.trim().length >= 3 &&
      _when != null &&
      _feeOk(_fee, _note);

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
        context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now);
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null) return;
    setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => context.read<RentalRepository>().walkIn(
            name: _name.text.trim(),
            contact: _contact.text.trim(),
            pickupAt: _when!,
            pickup: _pickup.text.trim(),
            destination: _destination.text.trim(),
            passengers: _count,
            fee: double.parse(_fee.text).toStringAsFixed(2),
            feeNote: _note.text.trim(),
          ),
      'Walk-in request entered with its fee. Assign its van and Dispatcher.',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void changed() => setState(() {});
    return AlertDialog(
      title: const Text('Walk-in special trip'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, onChanged: (_) => changed(), decoration: const InputDecoration(labelText: 'Customer name')),
            TextField(
                controller: _contact,
                onChanged: (_) => changed(),
                decoration: const InputDecoration(labelText: 'Contact number')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_when == null ? 'Pickup date and time' : DateFormat('EEE d MMM yyyy, h:mm a').format(_when!)),
              trailing: TextButton(onPressed: _pickWhen, child: Text(_when == null ? 'Choose' : 'Change')),
            ),
            TextField(controller: _pickup, onChanged: (_) => changed(), decoration: const InputDecoration(labelText: 'Pickup address')),
            TextField(
                controller: _destination,
                onChanged: (_) => changed(),
                decoration: const InputDecoration(labelText: 'Destination')),
            Row(children: [
              const Expanded(child: Text('Passengers (at most 14)')),
              IconButton(onPressed: _count > 1 ? () => setState(() => _count--) : null, icon: const Icon(Icons.remove)),
              Text('$_count'),
              IconButton(onPressed: _count < 14 ? () => setState(() => _count++) : null, icon: const Icon(Icons.add)),
            ]),
            _FeeFields(fee: _fee, note: _note, onChanged: changed),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _ok && !_busy ? _save : null, child: const Text('Enter request')),
      ],
    );
  }
}
