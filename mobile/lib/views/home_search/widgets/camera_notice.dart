import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../data/repositories/booking_repository.dart';

/// The notice on the booking screen (brief 4.5, 11): a camera at the van
/// door counts boardings. The period comes from A2Z's settings, so the
/// notice states the one in force; offline, it says so without a number.
class CameraNotice extends StatefulWidget {
  const CameraNotice({super.key});

  @override
  State<CameraNotice> createState() => _CameraNoticeState();
}

class _CameraNoticeState extends State<CameraNotice> {
  // Read once per app run: the settings rarely change.
  static Future<PrivacyNotice?>? _notice;

  @override
  void initState() {
    super.initState();
    _notice ??= BookingRepository(context.read<ApiClient>())
        .privacyNotice()
        .then<PrivacyNotice?>((n) => n)
        .catchError((Object _) {
      _notice = null; // try again next time
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<PrivacyNotice?>(
      future: _notice,
      builder: (_, snap) {
        final n = snap.data;
        final days = n?.retentionDays;
        // Four facts as a list under a title (20 Nov redesign), not one
        // long sentence: each can be found again at a glance.
        final lines = [
          'It counts people getting on and off, to check the passenger list.',
          'Faces are blurred on the phone, and no video leaves the van.',
          'A still of each boarding is kept for ${days != null ? '$days days' : 'a fixed number of days'}, '
              'unless a review is open.',
          'Only A2Z\'s Terminal Manager sees it. A sign in the van says the same.',
          if (n != null) 'Questions: ${n.privacyContact}.',
        ];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.infoContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.videocam_outlined, size: 20, color: AppColors.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Camera at the van door',
                      style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExcludeSemantics(child: Text('•  ', style: text.bodySmall)),
                  Expanded(child: Text(line, style: text.bodySmall)),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
