import '../../core/network/api_client.dart';
import '../../models/message_model.dart';

class MessagingRepository {
  MessagingRepository(this._api);
  final ApiClient _api;

  Future<List<Conversation>> listConversations() async {
    final json = await _api.get('/conversations') as List;
    return json.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<MessageContact>> listContacts() async {
    final json = await _api.get('/conversations/contacts') as List;
    return json.map((e) => MessageContact.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Conversation> startConversation({String? peerUserId, String? tripId}) async {
    final json = await _api.post('/conversations', body: {
      if (peerUserId != null) 'peer_user_id': peerUserId,
      if (tripId != null) 'trip_id': tripId,
    });
    return Conversation.fromJson(json as Map<String, dynamic>);
  }

  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final json = await _api.get('/conversations/$conversationId/messages') as List;
    return json.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChatMessage> sendMessage(String conversationId, String body) async {
    final json = await _api.post('/conversations/$conversationId/messages', body: {'body': body});
    return ChatMessage.fromJson(json as Map<String, dynamic>);
  }
}
