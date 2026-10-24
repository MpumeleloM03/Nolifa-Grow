import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncStatus.instance.reset();
  });
  tearDown(OfflineCache.clearAll); // also cancels any save still waiting

  group('a list with a cache key', () {
    test('keeps the last good rows on the phone', () async {
      final live = StreamController<List<Map<String, dynamic>>>();
      final rows = resilientRows(
        open: () => live.stream,
        fetch: () async => throw const FormatException('offline'),
        cacheKey: 'u1:water_zones',
      );
      final seen = <List<Map<String, dynamic>>>[];
      final sub = rows.listen(seen.add);
      live.add([
        {'id': 'dws-durban', 'data': {'latest': 90.9}}
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      final saved = await OfflineCache.load('u1:water_zones');
      expect(saved, isNotNull);
      expect(saved!.rows.single['id'], 'dws-durban');
      await sub.cancel();
      await live.close();
    });

    test('shows the saved rows first when the network never answers', () async {
      SharedPreferences.setMockInitialValues({
        'offline:v1:u1:traffic_incidents':
            '{"at": ${DateTime(2026, 10, 24, 14, 5).millisecondsSinceEpoch}, "rows": [{"id": "T1", "road": "N2"}]}',
      });
      final rows = resilientRows(
        open: () => Stream<List<Map<String, dynamic>>>.error(StateError('no signal')),
        fetch: () async => throw const FormatException('offline'),
        cacheKey: 'u1:traffic_incidents',
      );
      final first = await rows.first.timeout(const Duration(seconds: 3));
      expect(first.single['road'], 'N2');
      expect(SyncStatus.instance.value.offline, isTrue);
      expect(SyncStatus.instance.value.asOf, DateTime(2026, 10, 24, 14, 5));
    });

    test('live data replaces the saved copy and clears the offline flag', () async {
      SharedPreferences.setMockInitialValues({
        'offline:v1:u1:t': '{"at": ${DateTime(2026, 10, 24, 9).millisecondsSinceEpoch}, "rows": [{"id": "old"}]}',
      });
      final live = StreamController<List<Map<String, dynamic>>>();
      final seen = <String>[];
      final sub = resilientRows(
        open: () => live.stream,
        fetch: () async => const [],
        cacheKey: 'u1:t',
      ).listen((r) => seen.add(r.single['id'] as String));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      live.add([
        {'id': 'new'}
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen, ['old', 'new']);
      expect(SyncStatus.instance.value.offline, isFalse);
      await sub.cancel();
      await live.close();
    });

    test('a list without a key never touches storage', () async {
      final live = StreamController<List<Map<String, dynamic>>>();
      final sub = resilientRows(open: () => live.stream, fetch: () async => const []).listen((_) {});
      live.add([
        {'id': 'x'}
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('offline:')), isEmpty);
      await sub.cancel();
      await live.close();
    });
  });

  test('sign-out wipes every saved copy', () async {
    SharedPreferences.setMockInitialValues({
      'offline:v1:u1:a': '{"at": 1, "rows": []}',
      'offline:v1:u1:b': '{"at": 1, "rows": []}',
      'unrelated': 'keep',
    });
    await OfflineCache.clearAll();
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys(), {'unrelated'});
  });

  test('a copy that is too big to keep is skipped, not truncated', () async {
    final big = [
      for (var i = 0; i < 3000; i++) {'id': 'row$i', 'pad': 'x' * 300}
    ];
    OfflineCache.save('u1:big', big);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(await OfflineCache.load('u1:big'), isNull);
  });
}
