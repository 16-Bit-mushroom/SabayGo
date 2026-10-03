import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/walk_in_sync_service.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/shift_viewmodel.dart';

/// Record a cash passenger — at the terminal or flagged down en route.
///
/// A roadside pickup is anchored to the last terminal the van passed,
/// not the next one: anchoring forward would leave that stretch of road
/// looking empty while someone sits in it, and the camera check would
/// flag a real passenger as leakage. The conductor sets the fare because
/// the passenger has not travelled a fare-table distance.
///
/// Laid out as a till, for a queue at the van door (3 Oct):
///
/// * **Price before payment.** Each destination is a row that shows its
///   fare, and the total sits in a bar pinned above the button. The fare
///   used to appear only on the confirmation -- after the booking existed.
/// * **One tap per decision.** Destinations are all on screen as rows, not
///   inside a dropdown (two taps and a scroll). Boarding defaults to where
///   the van is and is rarely changed, so it is a compact chip row.
/// * **Optional things fold away.** Name, number and receipt are only for
///   a receipt; they sit collapsed below, not between the conductor and
///   the button.
/// * **Built for the next passenger.** After logging, "Next passenger"
///   clears the destination and keeps the screen; a run of walk-ins no
///   longer means backing out and re-opening it each time.
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key, required this.trip, this.roadside = false});

  final CrewTrip trip;
  final bool roadside;

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  late final WalkInSyncService _sync;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _landmark = TextEditingController();
  final _fare = TextEditingController();
  final _fareNote = TextEditingController();

  late int _boarding;
  int? _alighting;
  late bool _roadside;
  bool _wantsReceipt = false;
  bool _submitting = false;
  int _logged = 0;

  /// Null until loaded, and stays null offline: the screen then says the
  /// fare is set on sync rather than guessing one.
  Map<(int, int), double>? _fares;

  @override
  void initState() {
    super.initState();
    _sync = context.read<WalkInSyncService>();
    _roadside = widget.roadside;
    _boarding = context.read<ShiftViewModel>().currentStop;
    final last = _lastStop;
    if (_boarding >= last) _boarding = last - 1;
    // Most walk-ins ride to the end of the line; preselect it so the
    // common case is one tap (Log), and any other is two.
    _alighting = last > _boarding ? last : null;
    _fare.addListener(() => setState(() {}));
    _loadFares();
  }

  int get _lastStop {
    final stops = widget.trip.stops;
    if (stops.isEmpty) return _boarding + 1;
    return stops.map((s) => s.stopSequence).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _loadFares() async {
    try {
      final f = await OperationsRepository(context.read<ApiClient>()).fares(widget.trip.tripId);
      if (mounted) setState(() => _fares = f);
    } on ApiException {
      // Offline or not permitted: leave the preview off. Logging still
      // works -- the server prices it, now or when the queue syncs.
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _landmark, _fare, _fareNote]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _tableFare =>
      _alighting == null ? null : _fares?[(_boarding, _alighting!)];

  /// What the bar says to collect. Roadside: what the conductor typed.
  double? get _total => _roadside ? double.tryParse(_fare.text) : _tableFare;

  String _peso(double v) => '₱${v.toStringAsFixed(2)}';

  void _nextPassenger() {
    _form.currentState?.reset();
    for (final c in [_name, _phone, _landmark, _fare, _fareNote]) {
      c.clear();
    }
    setState(() {
      _wantsReceipt = false;
      // Boarding stop stays: the queue is at the same terminal.
      _alighting = _lastStop > _boarding ? _lastStop : null;
    });
  }

  Future<void> _submit() async {
    if (_alighting == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pick where the passenger is getting off.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final fareOverride = _roadside ? double.tryParse(_fare.text) : null;
      final submission = await _sync.submitOrQueue(
        tripId: widget.trip.tripId,
        boardingStop: _boarding,
        alightingStop: _alighting!,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        wantsReceipt: _wantsReceipt,
        isRoadsidePickup: _roadside,
        pickupLandmark: _landmark.text.trim(),
        fareOverride: fareOverride,
        fareNote: _fareNote.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _logged++;

      // The server's fare, not the preview, is what is confirmed: if the
      // two ever differ, the conductor collects what was recorded.
      final collect = submission.queued ? fareOverride ?? _tableFare : submission.result!.fare;
      final next = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => _LoggedSheet(
          queued: submission.queued,
          ticketNumber: submission.queued ? null : submission.result!.ticketNumber,
          collect: collect,
          manual: submission.queued ? fareOverride != null : submission.result!.fareIsManual,
          route: '${widget.trip.stopName(_boarding)} → ${widget.trip.stopName(_alighting!)}',
        ),
      );
      if (!mounted) return;
      if (next == true) {
        _nextPassenger();
      } else {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = [...widget.trip.stops]..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    final boardable = stops.where((s) => s.stopSequence < _lastStop).toList();
    final destinations = stops.where((s) => s.stopSequence > _boarding).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_roadside ? 'Roadside pickup' : 'Walk-in passenger'),
        actions: [
          if (_logged > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.gutter),
              child: Center(
                child: Text('$_logged logged',
                    style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _TotalBar(
        total: _total,
        pending: !_roadside && _alighting != null && _fares == null,
        manual: _roadside,
        submitting: _submitting,
        onSubmit: _submitting ? null : _submit,
        peso: _peso,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.storefront_outlined), label: Text('At terminal')),
                ButtonSegment(value: true, icon: Icon(Icons.pan_tool_alt_outlined), label: Text('Roadside')),
              ],
              selected: {_roadside},
              showSelectedIcon: false,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
              ),
              onSelectionChanged: (s) => setState(() => _roadside = s.first),
            ),
            if (_roadside)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Flagged down between terminals. Recorded from the last terminal passed, '
                    'with a fare you set.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),

            const SizedBox(height: AppSpacing.xl),
            _Heading(_roadside ? 'Last terminal passed' : 'Boarding at'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in boardable)
                  ChoiceChip(
                    label: Text(s.terminalName),
                    selected: _boarding == s.stopSequence,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: _boarding == s.stopSequence ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceRaised,
                    side: BorderSide(
                        color: _boarding == s.stopSequence ? AppColors.primary : AppColors.border),
                    onSelected: (_) => setState(() {
                      _boarding = s.stopSequence;
                      if (_alighting != null && _alighting! <= _boarding) {
                        _alighting = _lastStop > _boarding ? _lastStop : null;
                      }
                    }),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            const _Heading('Getting off at'),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < destinations.length; i++) ...[
                    if (i > 0) const Divider(),
                    _DestinationRow(
                      name: destinations[i].terminalName,
                      selected: _alighting == destinations[i].stopSequence,
                      // Roadside fares are the conductor's, so the table
                      // price would be misleading there.
                      fare: _roadside ? null : _fares?[(_boarding, destinations[i].stopSequence)],
                      peso: _peso,
                      onTap: () => setState(() => _alighting = destinations[i].stopSequence),
                    ),
                  ],
                ],
              ),
            ),

            if (_roadside) ...[
              const SizedBox(height: AppSpacing.xl),
              const _Heading('Fare charged'),
              TextFormField(
                controller: _fare,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 0) return 'Enter the fare you collected.';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _landmark,
                decoration: const InputDecoration(
                    labelText: 'Where they boarded', hintText: 'e.g. Ulas crossing, near the market'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _fareNote,
                decoration: const InputDecoration(
                    labelText: 'Fare note (optional)', hintText: 'e.g. half distance, student'),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            Theme(
              // The tile's own divider lines would double the card border.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Receipt details', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Optional: name and number, only for a receipt.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Mobile number'),
                    keyboardType: TextInputType.phone,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Wants a receipt'),
                    value: _wantsReceipt,
                    onChanged: (v) => setState(() => _wantsReceipt = v ?? false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted)),
      );
}

/// One destination: a full-width 56dp row, the terminal on the left and
/// its fare on the right. Selection is a filled radio *and* bold ink text,
/// not a tint alone, so it survives glare (WCAG 1.4.1).
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.name,
    required this.selected,
    required this.fare,
    required this.peso,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final double? fare;
  final String Function(double) peso;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: '$name${fare != null ? ', ${peso(fare!)}' : ''}',
        onTap: onTap, // restated: excludeSemantics drops the InkWell's own tap action
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: selected ? AppColors.primaryContainer : null,
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.primary : AppColors.border),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      )),
                ),
                if (fare != null)
                  Text(peso(fare!),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
              ],
            ),
          ),
        ),
      );
}

/// The till line: what to collect, and the button that records it. Pinned
/// so it never scrolls away and the thumb finds it in the same place for
/// every passenger.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.total,
    required this.pending,
    required this.manual,
    required this.submitting,
    required this.onSubmit,
    required this.peso,
  });

  final double? total;
  final bool pending;
  final bool manual;
  final bool submitting;
  final VoidCallback? onSubmit;
  final String Function(double) peso;

  @override
  Widget build(BuildContext context) {
    final caption = total != null
        ? (manual ? 'Conductor-set fare' : 'Approved fare')
        : pending
            ? 'Fare set by the server when logged'
            : manual
                ? 'Enter the fare you collected'
                : 'Pick a destination';
    return Material(
      color: AppColors.surfaceRaised,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COLLECT',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textMuted)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          total != null ? peso(total!) : '—',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(minimumSize: const Size(140, 56)),
                icon: submitting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(submitting ? 'Logging…' : 'Log'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmation after logging. The amount is the largest thing on it, so
/// the conductor can hold the phone up to the passenger. "Next passenger"
/// is the primary action because during a rush it is the common one.
class _LoggedSheet extends StatelessWidget {
  const _LoggedSheet({
    required this.queued,
    required this.ticketNumber,
    required this.collect,
    required this.manual,
    required this.route,
  });

  final bool queued;
  final String? ticketNumber;
  final double? collect;
  final bool manual;
  final String route;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(queued ? Icons.cloud_off : Icons.check_circle,
                    color: queued ? AppColors.warning : AppColors.success, size: 32),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(queued ? 'Logged offline' : 'Logged',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              Text(route, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
              if (ticketNumber != null)
                Text(ticketNumber!,
                    style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 15)),
              const SizedBox(height: AppSpacing.lg),
              const Text('COLLECT',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textMuted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  collect != null ? '₱${collect!.toStringAsFixed(2)}' : 'Fare set on sync',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1),
                ),
              ),
              if (manual)
                const Text('Conductor-set fare', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              if (queued) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'No connection right now. Saved on this phone; it syncs and gets a real '
                  'ticket number once you are back online.',
                  style: TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Next passenger'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
}
