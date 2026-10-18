import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components/empty_state.dart';
import '../../core/design/components/money.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/special_trip_repository.dart';

/// Rent the whole van (brief 2.5): request it -- when, pickup, destination,
/// how many, at most 14 -- and follow the request. A2Z agrees the fee by
/// pickup and destination and assigns a van; the fee is paid before the
/// van leaves, through the gateway here or in cash to the Dispatcher.
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

  Future<void> _pay(SpecialTripRequest r) => _run(() async {
        final url = await _repo.checkout(r.requestId);
        if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
          throw const ServerException('Could not open the payment page.');
        }
      }, '');

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Rent the whole van')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _new,
        icon: const Icon(Icons.add),
        label: const Text('Request a special trip'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null && list == null
            ? ListView(children: [AppEmptyState(icon: Icons.cloud_off, title: 'Could not load', body: _error!)])
            : list == null
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? ListView(children: const [
                        AppEmptyState(
                          icon: Icons.airport_shuttle_outlined,
                          title: 'No special trips yet',
                          body: 'Rent a van with its driver for up to 14 people, picked up where you choose.',
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

  Widget _card(SpecialTripRequest r) {
    final text = Theme.of(context).textTheme;
    final (label, tone) = switch (r.status) {
      'requested' => ('WAITING FOR A2Z', StatusTone.warning),
      'approved' => r.paymentStatus == 'paid' ? ('PAID', StatusTone.success) : ('APPROVED: PAY THE FEE', StatusTone.info),
      'rejected' => ('NOT POSSIBLE', StatusTone.danger),
      'completed' => ('DONE', StatusTone.muted),
      _ => ('WITHDRAWN', StatusTone.muted),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(_when.format(r.pickupAt), style: text.titleSmall)),
            StatusChip(label, tone: tone),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text('${r.pickupAddress} → ${r.destinationAddress}'),
          Text('${r.passengerCount} ${r.passengerCount == 1 ? 'passenger' : 'passengers'}', style: text.bodySmall),
          if (r.fee != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(child: Text(r.feeNote ?? 'Agreed fee', style: text.bodySmall)),
              Money(r.fee!, style: text.titleMedium!.copyWith(color: AppColors.primary)),
            ]),
          ],
          if (r.status == 'rejected')
            Text('A2Z could not take this one; their reason is in your updates.', style: text.bodySmall),
          if (r.canPay || r.canWithdraw) ...[
            const SizedBox(height: AppSpacing.md),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (r.canWithdraw)
                TextButton(
                  onPressed: _busy ? null : () => _run(() => _repo.withdraw(r.requestId), 'Request withdrawn.'),
                  child: const Text('Withdraw'),
                ),
              if (r.canPay)
                FilledButton(
                  onPressed: _busy ? null : () => _pay(r),
                  child: Text('Pay ${Money.format(r.fee!)}'),
                ),
            ]),
            if (r.canPay)
              Text('Pay before the van leaves, here or in cash to the Dispatcher.', style: text.bodySmall),
          ],
        ]),
      ),
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
      appBar: AppBar(title: const Text('Request a special trip')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            Text('A van and driver for your group only. A2Z agrees the fee with you by pickup and '
                'destination, and the fee is paid before the van leaves.', style: text.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_when == null ? 'Pickup date and time' : DateFormat('EEE d MMM yyyy, h:mm a').format(_when!)),
              trailing: TextButton(onPressed: _pickWhen, child: Text(_when == null ? 'Choose' : 'Change')),
            ),
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
            Row(children: [
              const Expanded(child: Text('Passengers (at most 14)')),
              IconButton(
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_count', style: text.titleMedium),
              IconButton(
                onPressed: _count < 14 ? () => setState(() => _count++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Send request')),
          ],
        ),
      ),
    );
  }
}
