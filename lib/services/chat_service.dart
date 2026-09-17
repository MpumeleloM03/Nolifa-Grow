import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import 'auth_service.dart';
import 'firebase_boot.dart';
import 'local_backend.dart';

/// Regional chat rooms, stored at chatRooms/{region}/messages.
///
/// Rooms are keyed by region so a farmer opens the app into the conversation
/// that actually affects them, rather than a national firehose.
class ChatService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _room(String region) =>
      _db.collection('chatRooms').doc(region).collection('messages');

  Stream<List<ChatMessage>> watch(String region, {int limit = 100}) {
    if (!FirebaseBoot.ready) return LocalBackend.instance.watchChat(region);
    return _room(region)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> send({
    required String region,
    required String uid,
    required String authorName,
    required String text,
    String kind = 'message',
  }) {
    if (!FirebaseBoot.ready) {
      return LocalBackend.instance.sendChat(
        region: region,
        uid: uid,
        authorName: authorName,
        text: text.trim(),
        kind: kind,
      );
    }
    return _room(region).add({
      'uid': uid,
      'authorName': authorName,
      'text': text.trim(),
      'kind': kind,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String region, String messageId) =>
      _room(region).doc(messageId).delete();
}

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

/// Which regional room the chat screen is showing.
final chatRoomProvider = StateProvider<String>((ref) => 'Greater Durban');

final chatStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, region) {
  return ref.watch(chatServiceProvider).watch(region);
});

/// Convenience for screens that need the signed-in farmer's display name.
final currentFarmerProvider = Provider<({String uid, String name})?>((ref) {
  final u = ref.watch(currentUserProvider);
  if (u == null) return null;
  final n = u.name.trim();
  return (uid: u.uid, name: n.isEmpty ? 'Farmer' : n);
});
