import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/walk_in_sync_service.dart';
import '../../data/repositories/operations_repository.dart';

/// Record a cash passenger boarding at the starting terminal.
///
/// Every passenger boards at the trip's first stop (rev 603, brief 2.4),
/// and the fare is always the approved one; the list closes at departure.
/// With [forEventId] the screen fixes the list for a boarding the camera
/// counted that matched no ticket or cash entry: it is sent at once, not
/// queued, because the server matches it to that boarding.
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
///   a receipt; they sit collapsed below, not between the Dispatcher and
///   the button.
/// * **Built for the next passenger.** After logging, "Next passenger"
///   clears the destination and keeps the screen; a run of walk-ins no
///   longer means backing out and re-opening it each time.
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key, required this.trip, this.forEventId});

  final CrewTrip trip;
  final String? forEventId;

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  late final WalkInSyncService _sync;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  late int _boarding;
  int? _alighting;
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
    _boarding = widget.trip.boardingStop;
    final last = _lastStop;
    // Most walk-ins ride to the end of the line; preselect it so the
    // common case is one tap (Log), and any other is two.
    _alighting = last > _boarding ? last : null;
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
    for (final c in [_name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  /// What the bar says to collect: the approved fare, once loaded.
  double? get _tableFare =>
      _alighting == null ? null : _fares?[(_boarding, _alighting!)];

  String _peso(double v) => '₱${v.toStringAsFixed(2)}';

  void _nextPassenger() {
    _form.currentState?.reset();
    for (final c in [_name, _phone]) {
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
      final forEvent = widget.forEventId;
      final submission = forEvent == null
          ? await _sync.submitOrQueue(
              tripId: widget.trip.tripId,
              boardingStop: _boarding,
              alightingStop: _alighting!,
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              wantsReceipt: _wantsReceipt,
            )
          : WalkInSubmission.submitted(await OperationsRepository(context.read<ApiClient>()).walkIn(
              tripId: widget.trip.tripId,
              boardingStop: _boarding,
              alightingStop: _alighting!,
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              wantsReceipt: _wantsReceipt,
              forEventId: forEvent,
            ));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _logged++;

      // The server's fare, not the preview, is what is confirmed: if the
      // two ever differ, the Dispatcher collects what was recorded.
      final collect = submission.queued ? _tableFare : submission.result!.fare;
      final next = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => _LoggedSheet(
          queued: submission.queued,
          ticketNumber: submission.queued ? null : submission.result!.ticketNumber,
          collect: collect,
          route: '${widget.trip.stopName(_boarding)} → ${widget.trip.stopName(_alighting!)}',
        ),
      );
      if (!mounted) return;
      if (next == true && forEvent == null) {
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
    final destinations = stops.where((s) => s.stopSequence > _boarding).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forEventId == null ? 'Walk-in passenger' : 'Add to the list'),
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
        total: _tableFare,
        pending: _alighting != null && _fares == null,
        submitting: _submitting,
        onSubmit: _submitting ? null : _submit,
        peso: _peso,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            _Heading('Boarding at ${widget.trip.stopName(_boarding)}'),
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
                      fare: _fares?[(_boarding, destinations[i].stopSequence)],
                      peso: _peso,
                      onTap: () => setState(() => _alighting = destinations[i].stopSequence),
                    ),
                  ],
                ],
              ),
            ),

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
    required this.submitting,
    required this.onSubmit,
    required this.peso,
  });

  final double? total;
  final bool pending;
  final bool submitting;
  final VoidCallback? onSubmit;
  final String Function(double) peso;

  @override
  Widget build(BuildContext context) {
    final caption = total != null
        ? 'Approved fare'
        : pending
            ? 'Fare set by the server when logged'
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
/// the Dispatcher can hold the phone up to the passenger. "Next passenger"
/// is the primary action because during a rush it is the common one.
class _LoggedSheet extends StatelessWidget {
  const _LoggedSheet({
    required this.queued,
    required this.ticketNumber,
    required this.collect,
    required this.route,
  });

  final bool queued;
  final String? ticketNumber;
  final double? collect;
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
