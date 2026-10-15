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
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.infoContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.videocam_outlined, size: 20, color: AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'A camera at the van door counts people getting on and off, to check the passenger '
                'list. No video leaves the van and no one is identified: the phone blurs faces and '
                'keeps only a still of each boarding, seen by A2Z\'s Terminal Manager alone, and '
                'deleted after ${days != null ? '$days days' : 'a fixed number of days'} unless a '
                'review is open. A sign in the van says the same.'
                '${n != null ? ' Questions: ${n.privacyContact}.' : ''}',
                style: text.bodySmall,
              ),
            ),
          ]),
        );
      },
    );
  }
}
