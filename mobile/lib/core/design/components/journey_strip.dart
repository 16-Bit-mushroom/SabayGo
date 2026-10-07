import 'package:flutter/material.dart';

import '../tokens.dart';

/// Boarding terminal above, alighting terminal below, joined by a rail.
///
/// This is the app's signature element and it was drawn six different ways:
/// the boarding pass used two `_buildInfoRow`s labelled "Origin" and
/// "Destination", the reservations card stacked two icons with an
/// `Icons.more_vert` between them as a connector, and the reschedule sheet
/// put an arrow in a sentence. A passenger reading a ticket, then a booking,
/// then a reschedule saw three unrelated pictures of the same fact.
///
/// The rail is drawn from two markers and a line rather than icons: a ring
/// for where you get on, a solid block for where you get off. That reads as
/// a direction of travel without a word of explanation, and it does not
/// depend on an icon font resolving.
///
/// A results row keeps its own one-line `A → B` form — a list of twelve
/// departures has no room for a two-line strip per row, and cramming one in
/// would cost the scannability the list exists for.
class JourneyStrip extends StatelessWidget {
  const JourneyStrip({
    required this.origin,
    required this.destination,
    this.originNote,
    this.destinationNote,
    super.key,
  });

  final String origin;
  final String destination;

  /// Under the terminal name: a departure time, "Board here", a stop label.
  final String? originNote;
  final String? destinationNote;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'From $origin${originNote == null ? '' : ', $originNote'}. '
          'To $destination${destinationNote == null ? '' : ', $destinationNote'}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Node(
            end: JourneyEnd.boarding,
            name: origin,
            note: originNote,
          ),
          // A fixed segment rather than a stretching one. The rail is a
          // hint about direction, not a measure of distance, and a line
          // that grows when a terminal name wraps to two lines draws the
          // eye to the wrapping instead of the journey.
          const _Rail(),
          _Node(
            end: JourneyEnd.alighting,
            name: destination,
            note: destinationNote,
          ),
        ],
      ),
    );
  }

}

const double _railWidth = JourneyMarker.size;
const double _railGap = AppSpacing.md;

/// Which end of a journey a marker stands for.
enum JourneyEnd {
  /// Where you get on: a ring, open, not yet used.
  boarding,

  /// Where you get off: closed, solid, the end of the line.
  alighting,
}

/// The dot beside a terminal name.
///
/// Public because the search fields draw the same two shapes beside the
/// same two terminals. Drawn here once, or the ring on the search form and
/// the ring on the ticket drift a pixel apart and look like different
/// things.
class JourneyMarker extends StatelessWidget {
  const JourneyMarker(this.end, {super.key});

  final JourneyEnd end;

  /// Both markers occupy this, so text beside them lines up whichever end
  /// it is.
  static const double size = 13;

  @override
  Widget build(BuildContext context) => switch (end) {
        JourneyEnd.boarding => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand, width: 2.5),
            ),
          ),
        JourneyEnd.alighting => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      };
}

class _Node extends StatelessWidget {
  const _Node({required this.end, required this.name, this.note});

  final JourneyEnd end;
  final String name;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The marker is centred on the first line of text rather than on
        // the block, so it stays beside the terminal name when the note
        // below wraps.
        SizedBox(
          width: _railWidth,
          height: text.bodyLarge!.fontSize! * text.bodyLarge!.height!,
          child: Center(child: JourneyMarker(end)),
        ),
        const SizedBox(width: _railGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
              ),
              if (note != null)
                Text(note!, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _railWidth,
      height: AppSpacing.xxl,
      child: Center(
        child: Container(width: 2, color: AppColors.border),
      ),
    );
  }
}
