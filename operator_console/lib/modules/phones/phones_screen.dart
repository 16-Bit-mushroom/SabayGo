import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Phones (brief 5.5): A2Z's pool of in-van phones. The Terminal Manager
/// adds a phone (its token is shown once) and retires it; the office checks
/// a phone out to a Dispatcher and van after the setup check, and records
/// its return and condition. The phone's last report shows here: battery,
/// temperature, camera and GPS.
class PhonesScreen extends StatefulWidget {
  const PhonesScreen({super.key});

  @override
  State<PhonesScreen> createState() => _PhonesScreenState();
}

class _PhonesScreenState extends State<PhonesScreen> {
  late final DeviceRepository _devices = context.read<DeviceRepository>();
  List<Phone>? _phones;
  bool _loading = true;
  String? _error;

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
      final phones = await _devices.list();
      if (mounted) setState(() => _phones = phones);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final phones = _phones ?? const <Phone>[];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Phones',
            technicalNote: 'Edge_Devices · Device_Checkouts',
            description: 'The phones that ride in the vans. Check one out to a Dispatcher and van '
                'after the setup check, and record it when it comes back.',
            actions: [
              if (manager)
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add phone'),
                ),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          Expanded(
            child: _loading && _phones == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : phones.isEmpty
                        ? const EmptyState(
                            icon: Icons.phone_android,
                            title: 'No phones in the pool',
                            hint: 'The Terminal Manager adds each phone once.')
                        : ListView.separated(
                            itemCount: phones.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, i) =>
                                _PhoneCard(phone: phones[i], manager: manager, onChanged: _load),
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final picked = await showDialog<(String, String)>(context: context, builder: (_) => const _AddPhoneDialog());
    if (picked == null || !mounted) return;
    String? token;
    final ok = await runAction(
        context, () async => token = await _devices.add(model: picked.$1, android: picked.$2), 'Phone added.');
    if (!ok || !mounted) return;
    await showToken(context, token!);
    _load();
  }
}

/// The phone's token, shown once: it goes into the phone's app now.
Future<void> showToken(BuildContext context, String token) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.key, color: AppColors.warning),
        title: const Text('The phone\'s token'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Enter it in the phone\'s app now. It is shown only this once; only its '
                'fingerprint is kept. Issue a new one if it is lost.'),
            const SizedBox(height: AppSpacing.md),
            SelectableText(token, style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
          ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.phone, required this.manager, required this.onChanged});
  final Phone phone;
  final bool manager;
  final VoidCallback onChanged;

  static final _when = DateFormat('d MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = phone;
    final out = p.checkout;
    final badge = switch (p.status) {
      'checked_out' => const StatusBadge('Out with a van', tone: Tone.info),
      'retired' => const StatusBadge('Retired'),
      _ => const StatusBadge('In the office', tone: Tone.success),
    };
    final report = p.lastReportAt == null
        ? 'No report yet'
        : [
            'Last report ${_when.format(p.lastReportAt!)}',
            if (p.batteryPct != null) 'battery ${p.batteryPct} %',
            if (p.batteryTempC != null) '${p.batteryTempC!.toStringAsFixed(1)} °C',
            if (p.cameraOk != null) p.cameraOk! ? 'camera working' : 'camera NOT working',
            if (p.gpsOk != null) p.gpsOk! ? 'GPS working' : 'GPS NOT working',
          ].join(' · ');
    return Panel(
      title: [p.model, if (p.androidVersion != null) 'Android ${p.androidVersion}'].join(' · '),
      icon: Icons.phone_android,
      trailing: badge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (out != null)
          FactLine(Icons.airport_shuttle_outlined,
              'With ${out.plateNumber} and ${out.dispatcherName} since ${_when.format(out.at)}'),
        FactLine(Icons.monitor_heart_outlined, report,
            colour: p.silent && p.status == 'checked_out' ? AppColors.danger : null),
        if (p.silent && p.status == 'checked_out')
          FactLine(Icons.wifi_off, 'Silent: no report within the set gap. The trip may go Unaudited.',
              colour: AppColors.danger),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, children: [
          if (p.status == 'in_office')
            FilledButton.tonalIcon(
              onPressed: () => _checkout(context),
              icon: const Icon(Icons.outbox_outlined, size: 18),
              label: const Text('Check out'),
            ),
          if (p.status == 'checked_out')
            FilledButton.tonalIcon(
              onPressed: () => _return(context),
              icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
              label: const Text('Record return'),
            ),
          if (manager && p.status != 'retired') ...[
            OutlinedButton(onPressed: () => _newToken(context), child: const Text('Issue new token')),
            if (p.status == 'in_office')
              OutlinedButton(
                onPressed: () => _retire(context),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Retire'),
              ),
          ],
        ]),
      ]),
    );
  }

  Future<void> _checkout(BuildContext context) async {
    final devices = context.read<DeviceRepository>();
    final picked = await showDialog<(String, String)>(context: context, builder: (_) => const _CheckoutDialog());
    if (picked == null || !context.mounted) return;
    var warnings = const <String>[];
    final ok = await runAction(context, () async {
      warnings = await devices.checkout(phone.deviceId, vanId: picked.$1, dispatcherId: picked.$2);
    }, 'Phone checked out.');
    if (!ok || !context.mounted) return;
    onChanged();
    if (warnings.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: const Text('Checked out, with warnings'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text('• $w')),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _return(BuildContext context) async {
    final devices = context.read<DeviceRepository>();
    final note = await askText(context,
        title: 'Record the phone\'s return',
        intro: 'The phone is back in the office. Note its condition.',
        label: 'Condition',
        confirmLabel: 'Record return',
        required: false);
    if (note == null || !context.mounted) return;
    if (await runAction(context, () => devices.giveBack(phone.deviceId, note: note), 'Return recorded.')) {
      onChanged();
    }
  }

  Future<void> _newToken(BuildContext context) async {
    final devices = context.read<DeviceRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue a new token?'),
        content: const Text('The phone\'s old token stops working at once. Enter the new one in the '
            'phone\'s app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Issue token')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    String? token;
    if (await runAction(context, () async => token = await devices.reissueToken(phone.deviceId),
            'New token issued.') &&
        context.mounted) {
      await showToken(context, token!);
    }
  }

  Future<void> _retire(BuildContext context) async {
    final devices = context.read<DeviceRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retire this phone?'),
        content: const Text('It leaves the pool for good and uploads nothing more. Its records stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await runAction(context, () => devices.retire(phone.deviceId), 'Phone retired.')) onChanged();
  }
}

class _AddPhoneDialog extends StatefulWidget {
  const _AddPhoneDialog();

  @override
  State<_AddPhoneDialog> createState() => _AddPhoneDialogState();
}

class _AddPhoneDialogState extends State<_AddPhoneDialog> {
  final _model = TextEditingController();
  final _android = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    _android.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a phone to the pool'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _model,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Model', hintText: 'realme 8 5G'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _android, decoration: const InputDecoration(labelText: 'Android version (optional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _model.text.trim().length >= 2
              ? () => Navigator.pop(context, (_model.text.trim(), _android.text.trim()))
              : null,
          child: const Text('Add phone'),
        ),
      ],
    );
  }
}

/// A validated van and a validated Dispatcher, as assignment takes them.
class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog();

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  List<Van>? _vans;
  List<StaffMember>? _dispatchers;
  String? _van;
  String? _dispatcher;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fleet = context.read<FleetRepository>();
    Future.wait([fleet.listVans(), fleet.listCrew(role: 'dispatcher')]).then((r) {
      if (!mounted) return;
      setState(() {
        _vans = [for (final v in r[0] as List<Van>) if (v.operationalStatus == 'active') v];
        _dispatchers = [
          for (final d in r[1] as List<StaffMember>) if (d.employmentStatus == 'active') d
        ];
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Check out the phone'),
      content: SizedBox(
        width: 420,
        child: _error != null
            ? Text(_error!)
            : _vans == null
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Do the setup check first: auto-launch on, battery optimisation off, '
                        'location allowed all the time, the camera clear.'),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _van,
                      decoration: const InputDecoration(labelText: 'Van'),
                      items: [
                        for (final v in _vans!)
                          DropdownMenuItem(value: v.vanId, child: Text('${v.plateNumber} · ${v.operatorName ?? ''}')),
                      ],
                      onChanged: (v) => setState(() => _van = v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _dispatcher,
                      decoration: const InputDecoration(labelText: 'Dispatcher'),
                      items: [
                        for (final d in _dispatchers!) DropdownMenuItem(value: d.userId, child: Text(d.fullName)),
                      ],
                      onChanged: (v) => setState(() => _dispatcher = v),
                    ),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _van != null && _dispatcher != null ? () => Navigator.pop(context, (_van!, _dispatcher!)) : null,
          child: const Text('Check out'),
        ),
      ],
    );
  }
}
