import 'package:flutter/material.dart';

import '../tokens.dart';

/// A dot that breathes: a figure is live, kept up to date by the server
/// (visibility of system status). A ring swells out of it and fades every
/// 1.6 s. Still -- the dot alone -- when the platform asks for reduced
/// motion, or when [live] is false (the figure is stale or did not load).
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = AppColors.accent, this.live = true});

  final Color color;
  final bool live;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still || !widget.live) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LiveDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: 14,
          height: 14,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Stack(alignment: Alignment.center, children: [
              if (_c.value > 0)
                Container(
                  width: 6 + 8 * _c.value,
                  height: 6 + 8 * _c.value,
                  decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.45 * (1 - _c.value)), shape: BoxShape.circle),
                ),
              Container(
                  width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
            ]),
          ),
        ),
      );
}
