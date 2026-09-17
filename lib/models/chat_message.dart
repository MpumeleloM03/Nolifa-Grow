import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String uid;
  final String authorName;
  final String text;
  final DateTime createdAt;

  /// 'alert' messages are disease sightings and render with a warning treatment.
  final String kind;

  const ChatMessage({
    required this.id,
    required this.uid,
    required this.authorName,
    required this.text,
    required this.createdAt,
    required this.kind,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Farmer',
      text: d['text'] as String? ?? '',
      // Pending writes have a null serverTimestamp until the server confirms.
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      kind: d['kind'] as String? ?? 'message',
    );
  }
}
