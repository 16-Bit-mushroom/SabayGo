import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/app_card.dart';
import '../../core/design/components/picker_row.dart';
import '../../core/design/components/status_band.dart';
import '../../core/design/components/empty_state.dart';
import '../../core/design/components/money.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/special_trip_repository.dart';

/// Rent the whole van (brief 2.5): request it -- when, pickup, destination,
/// how many, at most 14 -- and follow the request. A2Z agrees the fee by
/// pickup and destination and assigns a van; the fee is paid in cash to
/// the Dispatcher at the terminal before the van leaves.
/// A van rental's state as its chip says it, shared with Profile's "Rented
/// vans". An approved request waiting for the cash is ochre: it waits on
/// the passenger.
(String, StatusTone) rentalStatus(SpecialTripRequest r) => switch (r.status) {
      'requested' => ('WAITING FOR A2Z', StatusTone.warning),
      'approved' => r.paymentStatus == 'paid' ? ('PAID', StatusTone.success) : ('APPROVED: PAY IN CASH', StatusTone.warning),
      'rejected' => ('NOT POSSIBLE', StatusTone.danger),
      'completed' => ('DONE', StatusTone.success),
      _ => ('WITHDRAWN', StatusTone.muted),
    };

class SpecialTripsScreen extends StatefulWidget {
  const SpecialTripsScreen({super.key});

  @override
  State<SpecialTripsScreen> createState() => _SpecialTripsScreenState();
}

class _SpecialTripsScreenState extends State<SpecialTripsScreen> {
  late final SpecialTripRepository _repo = SpecialTripRepository(context.read<ApiClient>());
  List<SpecialTripRequest>? _list;
  String? _error;
  bool _busy = false;

  static final _when = DateFormat('EEE d MMM, h:mm a');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.mine();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      if (done.isNotEmpty) _snack(done);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _new() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _RequestForm(repo: _repo)),
    );
    if (sent == true) {
      _snack('Request sent. A2Z will agree the fee with you and assign a van.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Rent a van')),
      // Only once there is a list: with none, the empty state's button is
      // the one way in, not a second copy of it (20 Nov, the owner).
      floatingActionButton: list == null || list.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _new,
              icon: const Icon(Icons.add),
              label: const Text('Request a van'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null && list == null
            ? ListView(children: [AppEmptyState(icon: Icons.cloud_off, title: 'Could not load', body: _error!)])
            : list == null
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? ListView(children: [
                        AppEmptyState(
                          icon: Icons.airport_shuttle_outlined,
                          title: 'No van rentals yet',
                          body: 'Rent a van with its driver for up to 14 people, picked up where you choose.',
                          fillViewport: false,
                          action: FilledButton.icon(
                            onPressed: _busy ? null : _new,
                            icon: const Icon(Icons.add),
                            label: const Text('Request a van'),
                          ),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (_, i) => _card(list[i]),
                      ),
      ),
    );
  }

  /// One request: its state and size on top, when and where, the agreed
  /// fee and what to do about it (20 Nov redesign). An approved request
  /// waiting for the cash is ochre, because it waits on the passenger.
  Widget _card(SpecialTripRequest r) {
    final text = Theme.of(context).textTheme;
    final (label, tone) = rentalStatus(r);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // spaceBetween, not a Spacer: a Spacer took half the row and cut the
        // chip to "WAITING FOR…" (20 Nov).
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: StatusChip(label, tone: tone)),
          const SizedBox(width: AppSpacing.sm),
          Text('${r.passengerCount} ${r.passengerCount == 1 ? 'passenger' : 'passengers'}', style: text.bodySmall),
        ]),
        const SizedBox(height: AppSpacing.md),
        Text(_when.format(r.pickupAt), style: text.titleSmall),
        const SizedBox(height: 2),
        Text('${r.pickupAddress} → ${r.destinationAddress}', style: text.bodyMedium),
        if (r.fee != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: Text(r.feeNote ?? 'Agreed fee', style: text.bodySmall)),
            Money(r.fee!, style: text.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ],
        if (r.status == 'rejected') ...[
          const SizedBox(height: AppSpacing.sm),
          Text('A2Z could not take this one; their reason is in your updates.', style: text.bodySmall),
        ],
        if (r.owesFee) ...[
          const SizedBox(height: AppSpacing.md),
          StatusBand(
            tone: StatusTone.warning,
            icon: Icons.payments_outlined,
            title: 'Pay ${Money.format(r.fee!)} in cash',
            body: 'To the Dispatcher at the terminal, before the van leaves. Someone may pay for you.',
          ),
        ],
        if (r.canWithdraw) ...[
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _busy ? null : () => _run(() => _repo.withdraw(r.requestId), 'Request withdrawn.'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                minimumSize: const Size(0, AppSizing.minTouchTarget),
              ),
              child: const Text('Withdraw request'),
            ),
          ),
        ],
      ]),
    );
  }
}

class _RequestForm extends StatefulWidget {
  const _RequestForm({required this.repo});
  final SpecialTripRepository repo;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _form = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  DateTime? _when;
  int _count = 1;
  bool _busy = false;

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: _when ?? now.add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
    if (time == null) return;
    setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (_when == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick the pickup date and time.'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.request(
        pickupAt: _when!,
        pickupAddress: _pickup.text.trim(),
        destinationAddress: _destination.text.trim(),
        passengerCount: _count,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a van')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.edge),
              ),
              child: Text(
                'A van and driver for your group only. A2Z agrees the fee with you by pickup and '
                'destination. Cash only: the fee is paid to the Dispatcher at the terminal before the van leaves.',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: EdgeInsets.zero,
              child: AppPickerRow(
                leading: const Icon(Icons.event, size: 16, color: AppColors.primary),
                label: 'Pickup date and time',
                value: _when == null ? null : DateFormat('EEE d MMM yyyy, h:mm a').format(_when!),
                placeholder: 'Choose',
                semanticHint: 'Opens the calendar',
                onTap: _pickWhen,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _pickup,
              decoration: const InputDecoration(labelText: 'Pickup address'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Where should the van pick you up?' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _destination,
              decoration: const InputDecoration(labelText: 'Destination'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Where are you going?' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Passengers', style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            // A big counter: two buttons a thumb can hit, the number between
            // them, and the limit said under it.
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(children: [
                IconButton.outlined(
                  tooltip: 'One passenger fewer',
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Column(children: [
                    Text('$_count',
                        style: text.headlineMedium!.copyWith(
                            fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                    Text('at most 14', style: text.bodySmall),
                  ]),
                ),
                IconButton.outlined(
                  tooltip: 'One passenger more',
                  onPressed: _count < 14 ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Send request')),
          ],
        ),
      ),
    );
  }
}
