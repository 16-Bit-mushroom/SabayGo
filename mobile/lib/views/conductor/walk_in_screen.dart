import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
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
  late int _alighting;
  late bool _roadside;
  bool _wantsReceipt = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _sync = context.read<WalkInSyncService>();
    _roadside = widget.roadside;
    final stops = widget.trip.stops;
    _boarding = context.read<ShiftViewModel>().currentStop;
    _alighting = stops.isEmpty ? _boarding + 1 : stops.last.stopSequence;
    if (_alighting <= _boarding) _alighting = _boarding + 1;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _landmark, _fare, _fareNote]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final fareOverride = _roadside ? double.tryParse(_fare.text) : null;
      final submission = await _sync.submitOrQueue(
        tripId: widget.trip.tripId,
        boardingStop: _boarding,
        alightingStop: _alighting,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        wantsReceipt: _wantsReceipt,
        isRoadsidePickup: _roadside,
        pickupLandmark: _landmark.text.trim(),
        fareOverride: fareOverride,
        fareNote: _fareNote.text.trim(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            submission.queued ? Icons.cloud_off : Icons.check_circle,
            color: submission.queued ? AppColors.textMuted : AppColors.accent,
            size: 40,
          ),
          title: Text(submission.queued ? 'Logged — offline' : 'Logged'),
          content: submission.queued
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No connection right now. Saved on this phone and will '
                      'sync — and get a real ticket number — once you\'re back '
                      'online.',
                    ),
                    if (fareOverride != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Collect ₱${fareOverride.toStringAsFixed(2)} (conductor-set)',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      submission.result!.ticketNumber,
                      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Collect ₱${submission.result!.fare.toStringAsFixed(2)}'
                      '${submission.result!.fareIsManual ? ' (conductor-set)' : ''}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
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
    final stops = widget.trip.stops;

    return Scaffold(
      appBar: AppBar(title: Text(_roadside ? 'Roadside pickup' : 'Walk-in passenger')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.trip.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Flagged down between terminals'),
              subtitle: const Text('Recorded from the last terminal passed, with a fare you set.'),
              value: _roadside,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _roadside = v),
            ),
            const SizedBox(height: 12),

            _label(_roadside ? 'Last terminal passed' : 'Boarding at'),
            DropdownButtonFormField<int>(
              initialValue: _boarding,
              items: [
                for (final s in stops)
                  if (s.stopSequence < (stops.isEmpty ? 99 : stops.last.stopSequence))
                    DropdownMenuItem(value: s.stopSequence, child: Text('${s.stopSequence}. ${s.terminalName}')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _boarding = v;
                  if (_alighting <= _boarding) _alighting = _boarding + 1;
                });
              },
            ),
            const SizedBox(height: 16),

            _label('Alighting at'),
            DropdownButtonFormField<int>(
              initialValue: _alighting,
              items: [
                for (final s in stops)
                  if (s.stopSequence > _boarding)
                    DropdownMenuItem(value: s.stopSequence, child: Text('${s.stopSequence}. ${s.terminalName}')),
              ],
              onChanged: (v) => v == null ? null : setState(() => _alighting = v),
            ),

            if (_roadside) ...[
              const SizedBox(height: 16),
              _label('Where they boarded'),
              TextFormField(
                controller: _landmark,
                decoration: const InputDecoration(hintText: 'e.g. Ulas crossing, near the market'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              _label('Fare charged (₱)'),
              TextFormField(
                controller: _fare,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0.00'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 0) return 'Enter the fare you collected.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _label('Fare note (optional)'),
              TextFormField(
                controller: _fareNote,
                decoration: const InputDecoration(hintText: 'e.g. half distance, student'),
              ),
            ],

            const SizedBox(height: 24),
            const Text(
              'Passenger details are optional — only needed for a receipt.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
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

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add),
              label: Text(_submitting ? 'Logging…' : 'Log passenger'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      );
}
