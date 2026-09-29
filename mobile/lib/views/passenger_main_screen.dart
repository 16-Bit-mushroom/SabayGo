import 'package:flutter/material.dart';

import '../core/design/tokens.dart';
import 'home_search/home_screen.dart';
import 'messages/conversations_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';
import 'reservations/reservations_screen.dart';

/// The passenger's shell: five places to be, and the bar that moves between
/// them.
///
/// It was a `TabBar` of five bare icons pinned to the top of the screen.
/// Three things were wrong with that, and they compound.
///
/// *Unlabelled.* An icon alone is a guess. A screen reader announced "Tab 3
/// of 5" because nothing named it, which fails WCAG 4.1.2, and a sighted
/// first-time passenger had no better information — an envelope and a bell
/// are not self-evidently "messages" and "updates".
///
/// *At the top.* The five most-used controls in the app sat at the far end
/// of the thumb's reach, on a screen held one-handed by someone often
/// carrying something in the other. Navigation belongs where the hand is.
///
/// *Tabs, semantically.* Tabs say "different views of one thing". These are
/// five separate destinations, which is what a navigation bar says.
///
/// [IndexedStack] keeps all five alive. A `TabBarView` rebuilt each screen
/// on return, so a passenger who searched for a departure, checked a ticket
/// and came back found their search gone and had to pick both terminals
/// again.
class PassengerMainScreen extends StatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  State<PassengerMainScreen> createState() => _PassengerMainScreenState();
}

class _PassengerMainScreenState extends State<PassengerMainScreen> {
  int _index = 0;

  /// Title, icon and label together, so a destination cannot end up with
  /// the wrong heading. The console learned this the hard way: two parallel
  /// lists and a hand-written index sent a variance alert to the wrong tab.
  static const _destinations = <_Destination>[
    _Destination(
      // The brand, once, on the screen a passenger opens the app to.
      title: 'SabayGo',
      label: 'Home',
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
    ),
    _Destination(
      // Not "Reservations": what a passenger has is a trip they are taking.
      title: 'My trips',
      label: 'Trips',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number,
    ),
    _Destination(
      title: 'Messages',
      label: 'Messages',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
    ),
    _Destination(
      title: 'Updates',
      label: 'Updates',
      icon: Icons.notifications_none,
      selectedIcon: Icons.notifications,
    ),
    _Destination(
      title: 'Profile',
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_index].title),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          ReservationsScreen(),
          ConversationsScreen(),
          NotificationsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        // A hairline, not a shadow. The bar has to separate from a list
        // scrolling underneath it; an elevation shadow on a white bar over a
        // near-white scaffold is a smudge, and it is the first thing to look
        // dated.
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
                tooltip: d.title,
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.title,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Heading in the app bar. Longer than [label] where that reads better.
  final String title;

  /// Under the icon, so it has to be short.
  final String label;

  final IconData icon;
  final IconData selectedIcon;
}
