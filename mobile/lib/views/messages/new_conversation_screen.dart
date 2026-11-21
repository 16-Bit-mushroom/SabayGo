import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../models/message_model.dart';
import 'conversation_thread_screen.dart';

/// Who this user is allowed to message: their assigned Dispatcher
/// for a trip they're actually on, plus the cooperative office. Never a
/// free-text search -- the pairing is role- and trip-scoped on the server.
class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  late final MessagingRepository _repo;
  late Future<List<MessageContact>> _contacts;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _repo = MessagingRepository(context.read<ApiClient>());
    _contacts = _repo.listContacts();
  }

  Future<void> _open(MessageContact c) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final conv = await _repo.startConversation(peerUserId: c.peerUserId, tripId: c.tripId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConversationThreadScreen(
            conversationId: conv.id,
            peerName: conv.peerName,
            peerRole: conv.peerRole,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New message')),
      body: FutureBuilder<List<MessageContact>>(
        future: _contacts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load contacts.\n${snapshot.error}', textAlign: TextAlign.center));
          }
          final contacts = snapshot.data ?? const [];
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Text('No one to message yet. Your trip\'s Dispatcher appears here once you hold a seat.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          // Who may be written to, as the server lists them: the
          // Dispatcher of a trip the passenger is on, and the office.
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            children: [
              Text('You can write to the Dispatcher of a trip you are on, or to the A2Z office.',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: AppSpacing.lg),
              for (final (i, c) in contacts.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                Material(
                  color: AppColors.surfaceRaised,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: const BorderSide(color: AppColors.edge),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primaryContainer,
                      child: Icon(_iconFor(c.peerRole), color: AppColors.primary),
                    ),
                    title: Text(c.peerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(c.tripLabel != null ? 'Dispatcher · ${c.tripLabel}' : _roleLabel(c.peerRole)),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.primary),
                    onTap: _starting ? null : () => _open(c),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(String role) {
    switch (role) {
      case 'terminal_manager':
      case 'cashier':
        return Icons.storefront;
      case 'dispatcher':
        return Icons.badge_outlined;
      // Legacy threads only: drivers have no accounts since migration 017.
      case 'driver':
        return Icons.airline_seat_recline_normal;
      case 'passenger':
        return Icons.person_outline;
      default:
        return Icons.person_outline;
    }
  }

  String _roleLabel(String role) => switch (role) {
        'terminal_manager' || 'cashier' => 'A2Z office',
        'dispatcher' => 'Dispatcher',
        _ => 'Passenger',
      };
}
