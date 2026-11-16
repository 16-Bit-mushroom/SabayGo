import 'package:flutter/material.dart';

import '../tokens.dart';

/// The top of every screen: what it is called, one plain sentence on what
/// it is for, and the screen's own buttons on the right.
///
/// Every screen used to build this row by hand -- three title sizes, a
/// Refresh that was an icon on one screen and a text button on the next,
/// and titles that did not match the sidebar ("Trip Dispatch Command"
/// under "Trip Dispatcher"). The title here should read exactly as the
/// sidebar entry does, so staff know they landed where they clicked.
///
/// [description] is written for someone new to the office: what they can
/// do here, in their words, not the system's. Since 12 Nov it sits behind
/// the (i) beside the title, shown on hover or tap, so a page opens on its
/// work rather than on a paragraph (the owner: "bulky subtext").
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String description;

  final List<Widget> actions;

  /// A step inside a page (Setup's Terminals, Timetable, ...): the title a
  /// size down, under the page's own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? AppSpacing.lg : AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                // The office's words only: system and table names belong to
                // the code and the manuscript, not the page (UI redesign v3).
                // A heading to a screen reader, so a page can be found by
                // its title.
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: compact ? text.titleLarge : text.headlineMedium),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                InfoTip(description, size: compact ? 18 : 20),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The Refresh button every data screen carries, the same everywhere.
class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key, required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
      );
}

/// The (i) that holds a page's or a box's explanation: hover it, focus it
/// with Tab, or tap it on a touch screen. It darkens and fills on hover so
/// it reads as something to point at.
class InfoTip extends StatefulWidget {
  const InfoTip(this.message, {super.key, this.size = 18});

  final String message;
  final double size;

  @override
  State<InfoTip> createState() => _InfoTipState();
}

class _InfoTipState extends State<InfoTip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (widget.message.trim().isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: widget.message,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: const Duration(milliseconds: 150),
      showDuration: const Duration(seconds: 12),
      preferBelow: true,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(color: AppColors.onFill, fontSize: 13.5, height: 1.45),
      child: Focus(
        child: MouseRegion(
          cursor: SystemMouseCursors.help,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover ? AppColors.primaryContainer : Colors.transparent,
            ),
            child: Icon(Icons.info_outline,
                size: widget.size, color: _hover ? AppColors.primary : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
