import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Reveal, SupabaseBoot, notifierProvider, resilientRows;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'auth_service.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;

class Notice {
  final int id;
  final String kind, title, body;
  final DateTime at;
  final bool read;
  const Notice(this.id, this.kind, this.title, this.body, this.at, this.read);

  factory Notice.fromRow(Map<String, dynamic> r) => Notice(
        (r['id'] as num).toInt(),
        r['kind'] as String,
        r['title'] as String,
        (r['body'] as String?) ?? '',
        DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
        r['read_at'] != null,
      );

  IconData get icon => switch (kind) {
        'farm_application' || 'driver_application' => Icons.verified_rounded,
        'membership' || 'plan' => Icons.workspace_premium_rounded,
        'order_new' => Icons.shopping_bag_rounded,
        'order_packed' || 'order_driver' || 'order_pickedup' => Icons.local_shipping_rounded,
        'order_delivered' => Icons.check_circle_rounded,
        'payout' => Icons.payments_rounded,
        'cold_alarm' => Icons.ac_unit_rounded,
        'truck' => Icons.fire_truck_rounded,
        'borehole' => Icons.water_rounded,
        _ => Icons.notifications_rounded,
      };

  Color get color => switch (kind) {
        'cold_alarm' => AppTheme.danger,
        'order_new' => AppTheme.warn,
        'farm_application' || 'driver_application' || 'membership' || 'payout' || 'order_delivered' => AppTheme.sprout,
        _ => AppTheme.plantAccent,
      };
}

/// Everything the server has told this person, newest first. Live: a new row
/// arrives the moment staff approve, an order moves or a room warms up.
final noticesProvider = StreamProvider<List<Notice>>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('notifications').stream(primaryKey: ['id']).eq('uid', uid).order('id', ascending: false).limit(60),
    fetch: () async => [for (final r in await db.from('notifications').select().eq('uid', uid).order('id', ascending: false).limit(60)) Map<String, dynamic>.from(r)],
    cacheKey: '$uid:notifications',
  ).map((rows) => ([for (final r in rows) Notice.fromRow(r)]..sort((a, b) => b.id.compareTo(a.id))));
});

final unreadNoticesProvider = Provider<int>((ref) => (ref.watch(noticesProvider).valueOrNull ?? const []).where((n) => !n.read).length);

/// Wrap the signed-in app in this. A new notice shows as a banner at once, and
/// as a phone notification if the app is in the background. Nothing has to be
/// refreshed: approvals, plans and orders are live streams.
class NoticesHost extends ConsumerStatefulWidget {
  final Widget child;
  const NoticesHost({super.key, required this.child});

  @override
  ConsumerState<NoticesHost> createState() => _NoticesHostState();
}

class _NoticesHostState extends ConsumerState<NoticesHost> with WidgetsBindingObserver {
  AppLifecycleState _life = AppLifecycleState.resumed;
  int? _seen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _life = state;

  String get _key => 'notice_seen:${ref.read(currentUserProvider)?.uid}';

  Future<void> _loadSeen() async {
    try {
      _seen = (await SharedPreferences.getInstance()).getInt(_key);
    } catch (_) {}
  }

  void _onNotices(List<Notice>? old, List<Notice> now) {
    if (now.isEmpty) return;
    final top = now.first.id;
    // The first batch after sign-in is history, not news.
    if (_seen == null) {
      _seen = old == null || old.isEmpty ? top : (old.first.id);
      if (old == null || old.isEmpty) {
        _save(top);
        return;
      }
    }
    final fresh = [for (final n in now) if (n.id > _seen! && !n.read) n]..sort((a, b) => a.id.compareTo(b.id));
    if (fresh.isEmpty) return;
    _seen = top;
    _save(top);
    for (final n in fresh.take(3)) {
      if (_life == AppLifecycleState.resumed) {
        _banner(n);
      } else {
        ref.read(notifierProvider).show(title: n.title, body: n.body);
      }
    }
  }

  Future<void> _save(int id) async {
    try {
      (await SharedPreferences.getInstance()).setInt(_key, id);
    } catch (_) {}
  }

  void _banner(Notice n) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 7),
      backgroundColor: AppTheme.sheet,
      content: Row(children: [
        Icon(n.icon, color: n.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(n.title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
            if (n.body.isNotEmpty) Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ]),
        ),
      ]),
      action: SnackBarAction(label: tr('Open'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticesScreen()))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Notice>>>(noticesProvider, (prev, next) {
      final now = next.valueOrNull;
      if (now != null) _onNotices(prev?.valueOrNull, now);
    });
    return widget.child;
  }
}

String _ago(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 24 * 60) return '${m ~/ 60} h ago';
  return '${m ~/ (24 * 60)} d ago';
}

class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list is reading it.
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (!mounted || !SupabaseBoot.ready) return;
      try {
        await SupabaseBoot.client.rpc('mark_notifications_read');
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(noticesProvider).valueOrNull ?? const <Notice>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), backgroundColor: Colors.transparent),
      body: AppBackdrop(
        child: SafeArea(
          child: list.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(AppTheme.s6), child: Text('Nothing yet. Approvals, orders, payouts and temperature alerts show up here the moment they happen.', textAlign: TextAlign.center, style: AppTheme.callout)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final n = list[i];
                    return Reveal(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: GlassCard(
                          tint: n.read ? null : n.color.withValues(alpha: 0.10),
                          padding: const EdgeInsets.all(AppTheme.s4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(n.icon, color: n.color),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(n.title, style: AppTheme.headline),
                                if (n.body.isNotEmpty) Text(n.body, style: AppTheme.footnote),
                                Text(_ago(n.at), style: AppTheme.caption),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
