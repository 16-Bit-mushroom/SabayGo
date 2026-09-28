import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../models/message_model.dart';
import 'conversation_thread_screen.dart';

/// Who this user is allowed to message: their assigned conductor/driver
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
            return const Center(child: Text('No one to message yet.'));
          }
          return ListView.separated(
            itemCount: contacts.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = contacts[i];
              return ListTile(
                leading: CircleAvatar(child: Icon(_iconFor(c.peerRole))),
                title: Text(c.peerName),
                subtitle: c.tripLabel != null ? Text(c.tripLabel!) : null,
                onTap: _starting ? null : () => _open(c),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String role) {
    switch (role) {
      case 'coop_admin':
        return Icons.storefront;
      case 'conductor':
        return Icons.badge_outlined;
      case 'driver':
        return Icons.airline_seat_recline_normal;
      case 'passenger':
        return Icons.person_outline;
      default:
        return Icons.person_outline;
    }
  }
}
