import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/notification_repository.dart';
import '../../viewmodels/notification_provider.dart';

/// Bell with an unread badge for the sidebar. Opens a panel listing the
/// office's notifications; a variance alert jumps to the audit queue.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.onOpenAudits});

  final VoidCallback onOpenAudits;

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationProvider, int>((p) => p.unreadCount);
    return Tooltip(
      message: unread == 0 ? 'Notifications' : '$unread unread',
      child: IconButton(
        onPressed: () => _openPanel(context),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          backgroundColor: const Color(0xFFBF616A),
          child: Icon(
            unread > 0 ? Icons.notifications_active : Icons.notifications_none,
            color: unread > 0 ? const Color(0xFFEBCB8B) : Colors.white54,
          ),
        ),
      ),
    );
  }

  Future<void> _openPanel(BuildContext context) {
    final provider = context.read<NotificationProvider>();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => ChangeNotifierProvider<NotificationProvider>.value(
        value: provider,
        child: _NotificationPanel(onOpenAudits: onOpenAudits),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({required this.onOpenAudits});

  final VoidCallback onOpenAudits;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationProvider>();
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 248, top: 16),
        child: Material(
          color: const Color(0xFF222736),
          elevation: 12,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 420,
            height: 560,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Text('Notifications',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (p.unreadCount > 0)
                        TextButton(
                          onPressed: p.markAllRead,
                          child: const Text('Mark all read'),
                        ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: p.isLoading ? null : p.refresh,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _body(context, p)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NotificationProvider p) {
    if (p.error != null && p.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load notifications.\n${p.error}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    if (p.isLoading && p.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (p.items.isEmpty) {
      return const Center(
        child: Text('Nothing yet. A flagged headcount will appear here.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.separated(
      itemCount: p.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _NotificationTile(
        n: p.items[i],
        onTap: () async {
          final n = p.items[i];
          await p.markRead(n);
          if (n.isVarianceAlert && context.mounted) {
            Navigator.of(context).pop();
            onOpenAudits();
          }
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = n.isVarianceAlert ? const Color(0xFFEBCB8B) : const Color(0xFF88C0D0);
    return ListTile(
      onTap: onTap,
      dense: true,
      tileColor: n.isRead ? null : accent.withValues(alpha: 0.06),
      leading: Icon(
        n.isVarianceAlert ? Icons.people_alt_outlined : Icons.info_outline,
        color: n.isRead ? Colors.white38 : accent,
        size: 20,
      ),
      title: Text(
        n.title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${n.message}\n${_relative(n.createdAt)}',
          style: const TextStyle(fontSize: 12, color: Colors.white60, height: 1.35),
        ),
      ),
      isThreeLine: true,
      trailing: n.isVarianceAlert
          ? const Icon(Icons.chevron_right, size: 18, color: Colors.white38)
          : null,
    );
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
