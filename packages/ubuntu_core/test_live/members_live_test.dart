// Calls the new database functions the way the apps do, with real sign-ins.
// Same setup as supabase_live_test.dart (run supabase/run_live_tests.sh).
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

final _url = Platform.environment['SUPABASE_URL'] ?? '';
final _anon = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
final _service = Platform.environment['SUPABASE_SERVICE_KEY'] ?? '';
final _run = DateTime.now().millisecondsSinceEpoch;
const _opts = AuthClientOptions(authFlowType: AuthFlowType.implicit);

Future<(SupabaseClient, String)> _user(String name, {Map<String, dynamic>? meta}) async {
  final c = SupabaseClient(_url, _anon, authOptions: _opts);
  final r = await c.auth.signUp(email: '$name-m$_run@example.com', password: 'test-pass-123');
  return (c, r.user!.id);
}

void main() {
  final skip = (_url.isEmpty || _anon.isEmpty || _service.isEmpty) ? 'needs a local Supabase' : null;

  test('membership, vet case, video quota, diagnosis, chat, visit', () async {
    final admin = SupabaseClient(_url, _service);
    final (farmer, fid) = await _user('mfarmer');
    final (vet, vid) = await _user('mvet');
    final (boss, bid) = await _user('mboss');
    await admin.from('vets').insert({'uid': vid, 'name': 'Dr Test'});
    await admin.from('admins').insert({'uid': bid});
    await admin.from('users').upsert({'uid': fid, 'data': {'region': 'Greater Durban'}});

    await expectLater(farmer.rpc('open_consult', params: {'p_title': 'Limp', 'p_description': '', 'p_animal_id': null, 'p_animal_label': '', 'p_species': ''}), throwsA(isA<PostgrestException>()));
    await farmer.rpc('join_membership', params: {'p_tier': 'max'});
    await boss.rpc('activate_membership', params: {'p_uid': fid, 'p_ref': 'EFT'});
    expect(await farmer.rpc('videos_left'), 15);

    final id = await farmer.rpc('open_consult', params: {'p_title': 'Limping cow', 'p_description': 'Front leg', 'p_animal_id': 'a1', 'p_animal_label': 'Bessie', 'p_species': 'Cow'}) as String;
    final path = '$fid/$id/v1.mp4';
    await farmer.storage.from('consult-videos').uploadBinary(path, Uint8List.fromList(List.filled(2048, 7)), fileOptions: const FileOptions(contentType: 'video/mp4'));
    await farmer.from('consult_videos').insert({'consult_id': id, 'farmer_id': fid, 'path': path, 'duration_s': 90, 'bytes': 2048});
    expect(await farmer.rpc('videos_left'), 14);

    // The vet can fetch the video, a stranger cannot.
    final bytes = await vet.storage.from('consult-videos').download(path);
    expect(bytes.length, 2048);
    final (other, _) = await _user('mother');
    await expectLater(other.storage.from('consult-videos').download(path), throwsA(anything));

    await vet.rpc('send_consult_message', params: {'p_consult': id, 'p_body': 'Looking now'});
    await vet.rpc('vet_answer', params: {
      'p_consult': id,
      'p_diagnosis': {'suspected': 'Foot rot', 'why': 'Swelling between claws', 'remedy': 'Clean and treat', 'howItHelps': 'Kills the bacteria', 'urgency': 'soon'},
    });
    final row = await farmer.from('consults').select().eq('id', id).single();
    expect(row['status'], 'answered');
    expect((row['diagnosis'] as Map)['suspected'], 'Foot rot');
    await farmer.rpc('send_consult_message', params: {'p_consult': id, 'p_body': 'Thank you'});
    expect((await farmer.from('consult_messages').select().eq('consult_id', id)).length, 2);

    await farmer.rpc('request_vet_visit', params: {'p_consult': id, 'p_preferred': '2026-12-01', 'p_notes': 'Gate 1'});
    await vet.rpc('book_vet_visit', params: {'p_consult': id, 'p_on': '2026-12-02', 'p_note': 'Morning'});
    expect((await farmer.from('consults').select().eq('id', id).single())['status'], 'visit_booked');
  });

  test('farm application with photos, review, then selling is approved', () async {
    final admin = SupabaseClient(_url, _service);
    final (farmer, fid) = await _user('afarmer');
    final (boss, bid) = await _user('aboss');
    await admin.from('admins').insert({'uid': bid});
    await farmer.rpc('save_application', params: {
      'p_data': {
        'fullName': 'A Farmer', 'idNumber': '8001015009087', 'phone': '0821234567', 'farmName': 'Hills', 'province': 'KwaZulu-Natal',
        'lat': -29.5, 'lng': 30.2, 'sizeHa': 14.5, 'farmKind': 'livestock', 'consent': true,
        'practices': {'feeds': ['Veld grazing'], 'vaccineProgramme': 'LSD yearly'}, 'products': ['Cattle'],
      },
    });
    await expectLater(farmer.rpc('submit_application'), throwsA(isA<PostgrestException>()));
    for (final k in ['id_front', 'selfie_with_id', 'land_photo', 'certificate']) {
      final p = '$fid/$k-1.jpg';
      await farmer.storage.from('verification').uploadBinary(p, Uint8List.fromList(List.filled(512, 1)), fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await farmer.rpc('add_application_file', params: {'p_kind': k, 'p_path': p});
    }
    await farmer.rpc('submit_application');
    // Staff can open the ID photo, other farmers cannot.
    expect((await boss.storage.from('verification').download('$fid/id_front-1.jpg')).length, 512);
    final (other, _) = await _user('aother');
    await expectLater(other.storage.from('verification').download('$fid/id_front-1.jpg'), throwsA(anything));
    await boss.rpc('review_application', params: {'p_uid': fid, 'p_decision': 'approved', 'p_note': ''});
    expect((await farmer.from('farm_applications').select().eq('uid', fid).single())['status'], 'approved');
    expect((await other.from('farm_profiles').select().eq('uid', fid).single())['data']['farmName'], 'Hills');
  });

  test('borehole quote with member discount, drilled, reserve collected', () async {
    final admin = SupabaseClient(_url, _service);
    final (farmer, fid) = await _user('bfarmer');
    final (boss, bid) = await _user('bboss');
    await admin.from('admins').insert({'uid': bid});
    await farmer.rpc('join_membership', params: {'p_tier': 'member'});
    await boss.rpc('activate_membership', params: {'p_uid': fid, 'p_ref': 'EFT'});
    final id = await farmer.rpc('request_borehole', params: {'p_purpose': 'farm', 'p_lat': -29.8, 'p_lng': 30.9, 'p_address': 'Road', 'p_phone': '082', 'p_notes': '', 'p_agree_reserve': true}) as String;
    await boss.rpc('quote_borehole', params: {'p_id': id, 'p_standard': 80000});
    final q = await farmer.from('borehole_requests').select().eq('id', id).single();
    expect(q['final_quote'], 72000);
    await farmer.rpc('accept_borehole_quote', params: {'p_id': id});
    await boss.rpc('mark_borehole_drilled', params: {'p_id': id});
    final res = await boss.from('water_reserves').select().eq('borehole_id', id).single();
    expect(res['litres_reserved'], 50000);
    await boss.rpc('log_collection', params: {'p_reserve': res['id'], 'p_litres': 10000, 'p_note': 'School'});
    expect((await boss.from('water_reserves').select().eq('id', res['id']).single())['litres_collected'], 10000);
  });
}
