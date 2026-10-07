import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/location/current_position.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/sos_repository.dart';

/// The SOS control (spec 2.3.5), shared by the crew manifest and the
/// passenger's live map.
///
/// Two taps, never one: the icon opens a sheet, and the alert goes out
/// only from the button inside it. A single-tap panic control on a screen
/// a conductor uses all day would cry wolf often enough that the office
/// stopped believing it.
class SosButton extends StatelessWidget {
  const SosButton({super.key, this.tripId, this.compact = true});

  /// The trip the person is on, when they are on one. The server checks
  /// they really are before accepting it.
  final String? tripId;
  final bool compact;

  Future<void> _open(BuildContext context) async {
    final api = context.read<ApiClient>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SosSheet(repository: SosRepository(api), tripId: tripId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Emergency',
        onPressed: () => _open(context),
        icon: const Icon(Icons.emergency_share, color: AppColors.danger),
      );
    }
    return FilledButton.icon(
      onPressed: () => _open(context),
      style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
      icon: const Icon(Icons.emergency_share),
      label: const Text('Emergency SOS'),
    );
  }
}

const _categories = <String, ({IconData icon, String label})>{
  'medical': (icon: Icons.medical_services_outlined, label: 'Medical'),
  'accident': (icon: Icons.car_crash_outlined, label: 'Accident'),
  'security': (icon: Icons.shield_outlined, label: 'Security'),
  'breakdown': (icon: Icons.build_outlined, label: 'Breakdown'),
  'other': (icon: Icons.priority_high, label: 'Other'),
};

class _SosSheet extends StatefulWidget {
  const _SosSheet({required this.repository, this.tripId});

  final SosRepository repository;
  final String? tripId;

  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> {
  final _note = TextEditingController();
  String _category = 'medical';
  bool _sending = false;
  SosResult? _result;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    // Best effort, and bounded: the office learning *something* now beats
    // learning the exact coordinates a minute from now. A refused or slow
    // GPS sends the alert without a position, and the console says so.
    final position = await CurrentPosition.tryResolve();
    try {
      final result = await widget.repository.raise(
        category: _category,
        tripId: widget.tripId,
        note: _note.text,
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracyM: position?.accuracy,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _result != null ? _sent(_result!) : _form(),
    );
  }

  Widget _form() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_share, color: AppColors.danger),
              const SizedBox(width: 8),
              const Text('Emergency SOS',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text(
            'The cooperative office is alerted immediately, and the '
            'emergency numbers on file are texted.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _categories.entries)
                ChoiceChip(
                  selected: _category == e.key,
                  onSelected: _sending ? null : (_) => setState(() => _category = e.key),
                  avatar: Icon(e.value.icon, size: 18),
                  label: Text(e.value.label),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: !_sending,
            maxLength: 255,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'What is happening? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.campaign),
              label: Text(_sending ? 'Sending…' : 'Send alert now'),
            ),
          ),
        ],
      );

  /// The confirmation repeats the server's own wording. It never claims a
  /// text message went out when the gateway refused it -- someone deciding
  /// whether to also phone for help needs the truth, not reassurance.
  Widget _sent(SosResult r) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.duplicate ? Icons.info_outline : Icons.check_circle,
                  color: AppColors.success),
              const SizedBox(width: 8),
              Text(r.duplicate ? 'Already reported' : 'Alert sent',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Text(r.message, style: const TextStyle(fontSize: 14, height: 1.4)),
          if (r.smsAttempted > r.smsSent) ...[
            const SizedBox(height: 12),
            for (final d in r.dispatches.where((d) => d.status != 'sent'))
              Text('${d.recipient}: ${d.status}${d.error == null ? '' : ' — ${d.error}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            const SizedBox(height: 4),
            const Text(
              'If nobody reaches you shortly, call for help directly.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      );
}
