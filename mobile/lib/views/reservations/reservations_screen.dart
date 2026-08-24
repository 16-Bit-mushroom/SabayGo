import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ticket_model.dart';
import '../../viewmodels/reservations_viewmodel.dart';
import '../ticket/ticket_screen.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  final ReservationsViewModel _viewModel = ReservationsViewModel();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // --- Pinned Active Reservation ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Reservation',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2D2059), letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 16),
                      _viewModel.activeTicket != null
                          ? _buildActiveTicketCard(context, _viewModel.activeTicket!)
                          : _buildEmptyActiveState(),
                    ],
                  ),
                ),
              ),
              // --- Sticky Tab Bar ---
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  TabBar(
                    indicatorColor: const Color(0xFF00A859),
                    labelColor: const Color(0xFF00A859),
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'Trip History'),
                      Tab(text: 'Canceled'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              _buildTicketList(_viewModel.historyTickets, isCanceled: false),
              _buildTicketList(_viewModel.cancelledTickets, isCanceled: true),
            ],
          ),
        ),
      ),
    );
  }

  // --- Active Ticket Card UI ---
  Widget _buildActiveTicketCard(BuildContext context, TicketModel ticket) {
    final trip = ticket.trip;
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => TicketScreen(bookedTrip: trip)),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF00A859),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: const Color(0xFF00A859).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                  child: const Text('UPCOMING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                ),
                Text(DateFormat('MMM dd').format(trip.departureTime), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.departure_board, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(trip.origin.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 11, top: 4, bottom: 4),
              child: Icon(Icons.more_vert, color: Colors.white54, size: 20),
            ),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(trip.destination.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Departure', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(DateFormat('hh:mm a').format(trip.departureTime), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Icon(Icons.qr_code, color: Colors.white, size: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyActiveState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
      child: Column(
        children: [
          Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No upcoming trips', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- History & Canceled List UI ---
  Widget _buildTicketList(List<TicketModel> tickets, {required bool isCanceled}) {
    if (tickets.isEmpty) {
      return Center(
        child: Text('No ${isCanceled ? 'canceled' : 'past'} reservations.', style: const TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: tickets.length,
      separatorBuilder: (context, index) => const Divider(height: 32),
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        final trip = ticket.trip;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isCanceled ? Colors.red.shade50 : Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(isCanceled ? Icons.cancel_outlined : Icons.check_circle_outline, color: isCanceled ? Colors.red : Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${trip.origin.name} to ${trip.destination.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM dd, yyyy • hh:mm a').format(trip.departureTime), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Ticket ID: ${ticket.ticketId}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Text('₱${trip.approximateFare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        );
      },
    );
  }
}

// Custom Delegate to make the TabBar sticky
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.grey.shade100, // Matches the scaffold background
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}