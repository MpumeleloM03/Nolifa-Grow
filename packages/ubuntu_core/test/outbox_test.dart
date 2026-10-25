import 'dart:io' show SocketException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  late OfflineOutbox box;
  late List<String> sent;
  var offline = false;
  var refuse = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    box = OfflineOutbox();
    sent = [];
    offline = false;
    refuse = false;
    box.currentUser = () => 'u1';
    box.sender = (w, _) async {
      if (offline) throw const SocketException('Failed host lookup');
      if (refuse) throw const PostgrestException(message: 'not allowed', code: '42501');
      sent.add(w.label);
    };
  });

  test('a change goes straight through when there is signal', () async {
    expect(await box.rpc('Vote', 'water_vote', {'p_zone': 'z'}), isTrue);
    expect(sent, ['Vote']);
    expect(box.value, 0);
  });

  test('with no signal it waits, and goes out in order when the signal returns', () async {
    offline = true;
    expect(await box.rpc('First', 'a', {}), isFalse);
    expect(await box.insert('Second', 'outbreaks', {'data': {}}), isFalse);
    expect(await box.upsert('Third', 'market_products', {'id': 'p'}), isFalse);
    expect(box.value, 3);
    expect(await box.flush(), 0, reason: 'still offline');
    expect(box.value, 3);
    offline = false;
    expect(await box.flush(), 3);
    expect(sent, ['First', 'Second', 'Third']);
    expect(box.value, 0);
  });

  test('a new change waits behind older ones so the order is kept', () async {
    offline = true;
    await box.rpc('Old', 'a', {});
    offline = false;
    expect(await box.rpc('New', 'a', {}), isFalse);
    await box.flush();
    expect(sent, ['Old', 'New']);
  });

  test('a change the server refuses is thrown now, not queued', () async {
    refuse = true;
    await expectLater(box.rpc('Nope', 'a', {}), throwsA(isA<PostgrestException>()));
    expect(box.value, 0);
  });

  test('a queued change the server later refuses is dropped, not retried for ever', () async {
    offline = true;
    await box.rpc('Doomed', 'a', {});
    offline = false;
    refuse = true;
    await box.flush();
    expect(box.value, 0);
    refuse = false;
    expect(await box.flush(), 0);
    expect(sent, isEmpty);
  });

  test('the queue survives a restart and belongs to one person', () async {
    offline = true;
    await box.rpc('Mine', 'a', {});
    final again = OfflineOutbox()
      ..sender = box.sender
      ..currentUser = () => 'u1';
    //  = box.sender;
    offline = false;
    expect(await again.flush(), 1);
    expect(sent, ['Mine']);

    offline = true;
    await box.rpc('Mine again', 'a', {});
    final other = OfflineOutbox()
      ..sender = box.sender
      ..currentUser = () => 'u2';
    //  = box.sender;
    offline = false;
    expect(await other.flush(), 0, reason: "another person's changes are never sent as theirs");
  });
}
