import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/util/pick_file.dart';
import '../../data/repositories/fleet_repository.dart';

/// The van's four photographs (brief 8): not part of an import, uploaded
/// afterwards. The van cannot be validated until all four are present,
/// and a new photograph returns a validated van to Pending.
class VanPhotosDialog extends StatefulWidget {
  const VanPhotosDialog({super.key, required this.van});
  final Van van;

  @override
  State<VanPhotosDialog> createState() => _VanPhotosDialogState();
}

class _VanPhotosDialogState extends State<VanPhotosDialog> {
  late Map<String, String> _photos = Map.of(widget.van.photos);
  String? _busy;
  bool _changed = false;

  static const _words = {'front': 'Front', 'rear': 'Rear', 'left': 'Left side', 'right': 'Right side'};

  Future<void> _upload(String side) async {
    final fleet = context.read<FleetRepository>();
    final file = await pickFile(accept: 'image/jpeg,image/png');
    if (file == null || !mounted) return;
    setState(() => _busy = side);
    final ok = await runAction(context, () => fleet.uploadVanPhoto(widget.van.vanId, side, file.bytes, file.name),
        '${_words[side]} photograph saved.');
    if (ok) {
      final vans = await fleet.listVans();
      final fresh = vans.where((v) => v.vanId == widget.van.vanId).firstOrNull;
      if (mounted && fresh != null) setState(() => _photos = Map.of(fresh.photos));
      _changed = true;
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('${widget.van.plateNumber} · photographs (${_photos.length} of 4)'),
      content: SizedBox(
        width: 620,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 4 / 3,
          children: [
            for (final side in Van.photoSides)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  if (_photos[side] case final url?)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Image.network('${AppConfig.serverRoot}$url', fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(child: Text('Could not load'))),
                    )
                  else
                    Center(child: Text('Missing', style: text.bodySmall)),
                  Positioned(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Row(children: [
                      Expanded(child: StatusBadge(_words[side]!)),
                      FilledButton.tonal(
                        onPressed: _busy == null ? () => _upload(side) : null,
                        child: Text(_busy == side ? 'Saving…' : _photos.containsKey(side) ? 'Replace' : 'Upload'),
                      ),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Done'))],
    );
  }
}
