import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/money.dart';
import '../../core/design/components/app_card.dart';
import '../../core/design/components/status_band.dart';
import '../../core/design/components/status_chip.dart';
import '../passenger_main_screen.dart';
import '../../core/design/tokens.dart';
import '../../core/location/current_position.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../models/uv_trip_model.dart';

/// Book for Someone Else (brief 2.6): a relative books the seat of a
/// disabled or elderly passenger who cannot come to the terminal. The
/// relative holds a seat too, pays for both, comes to the terminal first
/// and rides along; the van stops at a pin on the map for the passenger.
///
/// Two steps: who and where (name, contact, pin and note), then the two
/// booking codes. Both seats are paid in cash to the Dispatcher at the
/// terminal, and the Dispatcher marking them Paid activates the pickup. A
/// photo of a landmark near the pin can go to the Dispatcher in the chat;
/// it is not payment proof and nothing depends on it. A pin too far from
/// the route is refused by the server in its own words.
class HomePickupScreen extends StatefulWidget {
  const HomePickupScreen({super.key, required this.trip});
  final UvTripModel trip;

  @override
  State<HomePickupScreen> createState() => _HomePickupScreenState();
}

class _HomePickupScreenState extends State<HomePickupScreen> {
  late final BookingRepository _bookings = BookingRepository(context.read<ApiClient>());
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _note = TextEditingController();
  final _map = MapController();
  List<RouteStopDetail> _stops = const [];
  LatLng? _pin;
  bool _busy = false;
  HomePickupBooking? _booked;
  bool _photoSent = false;

  @override
  void initState() {
    super.initState();
    TripRepository(context.read<ApiClient>()).stops(widget.trip.id).then((stops) {
      if (mounted) setState(() => _stops = stops);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _contact, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  Future<void> _myLocation() async {
    final pos = await CurrentPosition.tryResolve();
    if (!mounted) return;
    if (pos == null) {
      _snack('Your location is not available. Tap the map where the passenger waits.');
      return;
    }
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _pin = here);
    _map.move(here, 16);
  }

  Future<void> _book() async {
    if (!_form.currentState!.validate()) return;
    if (_pin == null) {
      _snack('Tap the map where the passenger will wait.');
      return;
    }
    setState(() => _busy = true);
    try {
      final booked = await _bookings.bookHomePickup(
        tripId: widget.trip.id,
        alightingStop: widget.trip.alightingStop,
        name: _name.text.trim(),
        contact: _contact.text.trim(),
        latitude: _pin!.latitude,
        longitude: _pin!.longitude,
        note: _note.text.trim(),
      );
      if (mounted) setState(() => _booked = booked);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _landmarkPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _bookings.sendLandmarkPhoto(_booked!.pickupId, await picked.readAsBytes(), picked.name);
      if (!mounted) return;
      setState(() => _photoSent = true);
      _snack('Sent to the trip\'s Dispatcher in the chat.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book for someone else'),
        actions: [
          // Where the relative is in the two steps (20 Nov redesign).
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.gutter),
            child: Center(
              child: StatusChip(_booked == null ? 'STEP 1 OF 2' : 'STEP 2 OF 2', tone: StatusTone.brand),
            ),
          ),
        ],
      ),
      body: _booked == null ? _details() : _payment(_booked!),
    );
  }

  Widget _details() {
    final t = widget.trip;
    final text = Theme.of(context).textTheme;
    final start = _stops.isEmpty ? null : LatLng(_stops.first.latitude, _stops.first.longitude);
    return Form(
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
              'For a passenger who cannot come to the terminal because of age or disability. You take '
              'a seat too: you board at ${t.origin.name} and ride along, and the van stops for them on '
              'the way. You pay both seats in cash to the Dispatcher at the terminal.',
              style: text.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Passenger\'s name'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name.' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Their contact number'),
                validator: (v) => (v ?? '').trim().length < 7 ? 'Enter a number the Dispatcher can call.' : null,
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Where they will wait', style: text.titleSmall)),
                // Their own spot in one tap, for a relative who does not use
                // maps much.
                OutlinedButton.icon(
                  onPressed: _myLocation,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizing.minTouchTarget),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Here'),
                ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Text('Tap the map near the green line: the van\'s route to ${t.destination.name}.', style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: start == null
                      ? const Center(child: CircularProgressIndicator())
                      : FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: start,
                            initialZoom: 12,
                            onTap: (_, point) => setState(() => _pin = point),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ph.edu.umindanao.sabaygo',
                            ),
                            PolylineLayer(polylines: [
                              Polyline(
                                points: [for (final s in _stops) LatLng(s.latitude, s.longitude)],
                                strokeWidth: 5,
                                color: AppColors.primary,
                              ),
                            ]),
                            MarkerLayer(markers: [
                              for (final s in _stops)
                                Marker(
                                  point: LatLng(s.latitude, s.longitude),
                                  width: 14,
                                  height: 14,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  ),
                                ),
                              if (_pin != null)
                                Marker(
                                  point: _pin!,
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.topCenter,
                                  // The passenger's own place: pin red, the
                                  // route marker colour, not the SOS red.
                                  child: const Icon(Icons.location_pin, size: 40, color: AppColors.brand),
                                ),
                            ]),
                            const RichAttributionWidget(
                              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _note,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Note for the Dispatcher (optional)',
                  hintText: 'Green gate beside the sari-sari store',
                ),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('2 seats: ${t.origin.name} → ${t.destination.name}', style: text.titleSmall),
                  Text('Both paid in cash at the terminal', style: text.bodySmall),
                ]),
              ),
              const SizedBox(width: AppSpacing.md),
              Money(t.approximateFare * 2, style: text.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _book,
            child: Text(_busy ? 'Booking…' : 'Reserve both seats'),
          ),
        ],
      ),
    );
  }

  Widget _payment(HomePickupBooking b) {
    final text = Theme.of(context).textTheme;
    final name = _name.text.trim();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      children: [
        StatusBand(
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
          title: 'Both seats are reserved',
          body: 'Come to ${widget.trip.origin.name} before the van leaves and pay both fares in cash to the '
              'Dispatcher. Give them these codes or your name. Once they mark the seats Paid, the van stops '
              'for $name at the pin. Unpaid seats are released shortly before departure.',
          liveRegion: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final (label, seat) in [('Your seat (you board at ${widget.trip.origin.name})', b.relative),
          ('$name\'s seat (picked up at the pin)', b.passenger)]) ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(label, style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w600))),
                const SizedBox(width: AppSpacing.sm),
                const StatusChip('UNPAID', tone: StatusTone.warning),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(seat.bookingCode,
                        semanticsLabel: 'Booking code ${seat.bookingCode.split('').join(' ')}',
                        style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: seat.bookingCode));
                    _snack('Booking code copied.');
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSizing.minTouchTarget),
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ]),
              Money(seat.fare, style: text.bodyMedium!.copyWith(color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Help the Dispatcher find the place', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text('Send a photo of a landmark near the pin, such as a gate or a store. It goes to the trip\'s '
            'Dispatcher in your chat with them. A photo can show personal details: it is kept only for a '
            'limited number of days.', style: text.bodySmall),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _landmarkPhoto,
          icon: Icon(_photoSent ? Icons.check_circle_outline : Icons.image_outlined),
          label: Text(_photoSent ? 'Photo sent. Send another' : 'Send a landmark photo'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: () => PassengerMainScreen.goTo(context, PassengerMainScreen.trips),
          child: const Text('Go to My trips'),
        ),
      ],
    );
  }
}
