/// What a post in the community feed is about.
enum PostTopic { crop, livestock, water }

/// How the evidence was produced. Crop and livestock posts are checked by the
/// on-phone AI; water posts carry a photo and the reporter's own reading.
enum ProofKind { aiScan, symptomCheck, photoOnly }

class ProofPost {
  final String id;
  final String uid;
  final String author;
  final String region;
  final PostTopic topic;
  final String headline; // what the check found, or the water problem
  final String detail; // the reporter's note
  final String severity; // 'green' | 'orange' | 'red'
  final ProofKind proof;
  final String aiSummary; // e.g. "Scanned on this phone: Late Blight, 87%"
  final String? photoPath; // the photo they took, on their phone
  final String? emoji; // stands in for a photo on demo posts
  final DateTime at;
  final int confirmations;
  final bool iConfirmed;
  final bool demo;

  const ProofPost({
    required this.id,
    required this.uid,
    required this.author,
    required this.region,
    required this.topic,
    required this.headline,
    required this.detail,
    required this.severity,
    required this.proof,
    required this.aiSummary,
    required this.at,
    this.photoPath,
    this.emoji,
    this.confirmations = 0,
    this.iConfirmed = false,
    this.demo = false,
  });

  bool get urgent => severity == 'red';

  ProofPost copyWith({int? confirmations, bool? iConfirmed}) => ProofPost(
        id: id,
        uid: uid,
        author: author,
        region: region,
        topic: topic,
        headline: headline,
        detail: detail,
        severity: severity,
        proof: proof,
        aiSummary: aiSummary,
        at: at,
        photoPath: photoPath,
        emoji: emoji,
        confirmations: confirmations ?? this.confirmations,
        iConfirmed: iConfirmed ?? this.iConfirmed,
        demo: demo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'author': author,
        'region': region,
        'topic': topic.name,
        'headline': headline,
        'detail': detail,
        'severity': severity,
        'proof': proof.name,
        'ai': aiSummary,
        'photo': photoPath,
        'emoji': emoji,
        'at': at.millisecondsSinceEpoch,
        'confirmations': confirmations,
        'iConfirmed': iConfirmed,
        'demo': demo,
      };

  factory ProofPost.fromJson(Map<String, dynamic> m) => ProofPost(
        id: m['id'] as String,
        uid: m['uid'] as String? ?? '',
        author: m['author'] as String? ?? 'Farmer',
        region: m['region'] as String? ?? '',
        topic: PostTopic.values.firstWhere((t) => t.name == m['topic'], orElse: () => PostTopic.crop),
        headline: m['headline'] as String? ?? '',
        detail: m['detail'] as String? ?? '',
        severity: m['severity'] as String? ?? 'orange',
        proof: ProofKind.values.firstWhere((t) => t.name == m['proof'], orElse: () => ProofKind.photoOnly),
        aiSummary: m['ai'] as String? ?? '',
        photoPath: m['photo'] as String?,
        emoji: m['emoji'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        confirmations: (m['confirmations'] as num?)?.toInt() ?? 0,
        iConfirmed: m['iConfirmed'] as bool? ?? false,
        demo: m['demo'] as bool? ?? false,
      );
}

/// The filters on the community feed.
enum FeedFilter { crops, livestock, both, water }

extension FeedFilterX on FeedFilter {
  String get label => switch (this) {
        FeedFilter.crops => 'Crops',
        FeedFilter.livestock => 'Livestock',
        FeedFilter.both => 'Both',
        FeedFilter.water => 'Water',
      };

  bool matches(PostTopic t) => switch (this) {
        FeedFilter.crops => t == PostTopic.crop,
        FeedFilter.livestock => t == PostTopic.livestock,
        FeedFilter.both => t == PostTopic.crop || t == PostTopic.livestock,
        FeedFilter.water => t == PostTopic.water,
      };
}

/// Most important first: urgent, then watch, then the rest, newest within each.
List<ProofPost> rankPosts(Iterable<ProofPost> posts) {
  int weight(ProofPost p) => switch (p.severity) { 'red' => 0, 'orange' => 1, _ => 2 };
  final list = [...posts];
  list.sort((a, b) {
    final w = weight(a).compareTo(weight(b));
    return w != 0 ? w : b.at.compareTo(a.at);
  });
  return list;
}
