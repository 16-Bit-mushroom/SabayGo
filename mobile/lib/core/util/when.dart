/// How this app writes times and dates.
///
/// There were twenty-three different format strings across `lib/views` for
/// what are really four facts. The boarding pass said `05:30 AM` while the
/// results list said `5:30 AM`; the manifest wrote `MMM dd • hh:mm a` and
/// the remittance screen `EEE, MMM d • hh:mm a`. Each was reasonable alone,
/// and together they made one system look like four.
///
/// Rules, applied everywhere:
///
/// * No padded hour. A clock face shows 5:30, not 05:30, and the zero costs
///   a character in exactly the place a passenger glances fastest.
/// * The separator is a middle dot, `·`, never a bullet.
/// * Today and tomorrow are named, not dated. Most bookings are for one of
///   the two, and "Today" is read in less time than any date can be.
///
/// All times are Asia/Manila local, which is how MySQL stores them — see
/// `app.core.timezone` on the server. Nothing here converts a zone, and
/// nothing should: a departure at 05:30 is 05:30 at the terminal.
library;

import 'package:intl/intl.dart';

/// `5:30 AM`
String clockTime(DateTime dt) => DateFormat('h:mm a').format(dt);

/// `Sat, 4 Oct`
String dayShort(DateTime dt) => DateFormat('EEE, d MMM').format(dt);

/// `Today, 4 Oct` · `Tomorrow, 5 Oct` · `Saturday, 8 Oct`
///
/// For a date the passenger is choosing or has chosen, where the weekday is
/// worth spelling out.
String dayFriendly(DateTime dt) {
  final date = DateFormat('d MMM').format(dt);
  return switch (_daysFromToday(dt)) {
    0 => 'Today, $date',
    1 => 'Tomorrow, $date',
    _ => DateFormat('EEEE, d MMM').format(dt),
  };
}

/// `Today · 5:30 AM` · `Sat, 4 Oct · 5:30 AM`
///
/// For a departure in a list, where the day is context and the time is the
/// fact.
String dayAndTime(DateTime dt) {
  final time = clockTime(dt);
  return switch (_daysFromToday(dt)) {
    0 => 'Today · $time',
    1 => 'Tomorrow · $time',
    _ => '${dayShort(dt)} · $time',
  };
}

/// Calendar days from today, so a departure four hours from now that falls
/// after midnight still counts as tomorrow. Comparing instants instead of
/// dates is how "Today, 1 Oct" ends up on a trip leaving on the 2nd.
int _daysFromToday(DateTime dt) {
  final now = DateTime.now();
  return DateTime(dt.year, dt.month, dt.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
}
