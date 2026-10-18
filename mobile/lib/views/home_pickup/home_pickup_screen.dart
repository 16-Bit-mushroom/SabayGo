import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components/money.dart';
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
/// Two steps: who and where (name, contact, pin and note), then payment --
/// each seat through the gateway, or, when the gateway is down, a
/// screenshot of the payment sent to the trip's Dispatcher, who confirms
/// it. A pin too far from the route is refused by the server in its own
/// words.
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
  bool _proofSent = false;

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

  Future<void> _pay(ReservationResult seat) async {
    setState(() => _busy = true);
    try {
      final url = await _bookings.startCheckout(seat.bookingId);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open the payment page.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _screenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _bookings.sendPaymentScreenshot(_booked!.pickupId, await picked.readAsBytes(), picked.name);
      if (!mounted) return;
      setState(() => _proofSent = true);
      _snack('Sent to the trip\'s Dispatcher. Both seats are held until departure while they check it.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book for someone else')),
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
          Text('For a passenger who cannot come to the terminal because of age or disability. You take '
              'a seat too: you board at ${t.origin.name} and ride along, and the van stops for them on '
              'the way. You pay for both seats.', style: text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
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
          const SizedBox(height: AppSpacing.lg),
          Row(children: [
            Expanded(child: Text('Where they will wait', style: text.titleSmall)),
            TextButton.icon(onPressed: _myLocation, icon: const Icon(Icons.my_location, size: 18), label: const Text('Here')),
          ]),
          Text('Tap the map. It must be near the van\'s route to ${t.destination.name}.', style: text.bodySmall),
          const SizedBox(height: AppSpacing.sm),
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
                            strokeWidth: 4,
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
                              child: const Icon(Icons.location_pin, size: 40, color: AppColors.danger),
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
          const SizedBox(height: AppSpacing.md),
          Text('2 seats: ${t.origin.name} → ${t.destination.name}', style: text.titleSmall),
          Row(children: [
            const Expanded(child: Text('Total for both')),
            Money(t.approximateFare * 2, style: text.titleLarge!.copyWith(color: AppColors.primary)),
          ]),
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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      children: [
        Text('Both seats are held. Pay for each one.', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Find both tickets on the Trips tab. Scan yours at ${widget.trip.origin.name}: that tells the '
            'Dispatcher to stop for ${_name.text.trim()}. Their ticket is not scanned at the terminal.',
            style: text.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        for (final (label, seat) in [('Your seat', b.relative), ('${_name.text.trim()}\'s seat', b.passenger)])
          Card(
            child: ListTile(
              title: Text(label),
              subtitle: Text(seat.ticketNumber),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _pay(seat),
                child: Text('Pay ${Money.format(seat.fare)}'),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Payment page not working?', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text('Pay A2Z another digital way and send a screenshot of the payment. It goes to the trip\'s '
            'Dispatcher in your chat with them; they confirm it. A screenshot can show personal details: '
            'it is kept only for a limited number of days.', style: text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _screenshot,
          icon: Icon(_proofSent ? Icons.check_circle_outline : Icons.image_outlined),
          label: Text(_proofSent ? 'Screenshot sent. Send another' : 'Send a payment screenshot'),
        ),
        const SizedBox(height: AppSpacing.xl),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
