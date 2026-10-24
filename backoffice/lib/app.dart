import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as sb show User, AuthException;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'pages/admin_pages.dart';
import 'pages/certs_page.dart';
import 'pages/vet_page.dart';
import 'pages/orders_page.dart';
import 'pages/overview_page.dart';
import 'pages/receiving_page.dart';
import 'pages/rooms_page.dart';
import 'pages/scan_page.dart';
import 'pages/stock_page.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
SupabaseClient get _db => SupabaseBoot.client;

final authUserProvider = StreamProvider<sb.User?>((ref) => _db.auth.onAuthStateChange.map((e) => e.session?.user));

/// Wires the shared package into the staff member's own sign-in and the shared
/// Supabase database. No demo content, ever.
List<Override> backOfficeOverrides() => [
      ...liveOverrides(() => true),
      marketUidProvider.overrideWith((ref) => ref.watch(authUserProvider).valueOrNull?.id ?? 'guest'),
      marketNameProvider.overrideWith((ref) {
        final u = ref.watch(authUserProvider).valueOrNull;
        final n = ((u?.userMetadata?['name'] as String?) ?? u?.email ?? 'Staff').split('@').first;
        return n.isEmpty ? 'Staff' : n;
      }),
      marketRepositoryProvider.overrideWith((ref) => SupabaseMarketRepository()),
      waterRepositoryProvider.overrideWith((ref) => SupabaseWaterRepository()),
    ];

class BackOfficeApp extends StatelessWidget {
  const BackOfficeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Nolifa Back Office',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.buildLight(),
        home: const _Gate(),
      );
}

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    return user.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e, doing: 'start')))),
      data: (u) => u == null ? const LoginPage() : SecondFactorGuard(key: ValueKey('2fa-${u.id}'), child: const _Access()),
    );
  }
}

/// Signed in is not enough: an admin has to have added this person.
class _Access extends ConsumerWidget {
  const _Access();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(staffRolesProvider);
    return roles.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e, doing: 'check your access')))),
      data: (r) => (r.hub || r.certifier || r.admin || r.vet)
          ? Shell(roles: r)
          : Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('No access yet', style: AppTheme.title1),
                      const SizedBox(height: 8),
                      Text(
                          'You are signed in as ${_db.auth.currentUser?.email}. A Nolifa admin has to add you as staff, a certifier, a vet or an admin before you can use the back office. '
                          'Send them this ID: ${_db.auth.currentUser?.id}',
                          style: AppTheme.callout),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _db.auth.signOut, child: const Text('Sign out')),
                    ]),
                  ),
                ),
              ),
            ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
    } on sb.AuthException catch (e) {
      setState(() => _error = e.message.toLowerCase().contains('invalid')
          ? 'Check your email and password.'
          : 'We could not sign you in. Try again.');
    } catch (_) {
      setState(() => _error = 'We could not reach the server. Check your connection, then try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Nolifa Back Office', style: AppTheme.title1),
                const SizedBox(height: 4),
                Text('Warehouse staff and certifiers', style: AppTheme.callout),
                const SizedBox(height: 24),
                TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                TextField(
                    controller: _pass,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onSubmitted: (_) => _go()),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: AppTheme.danger))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'Signing in...' : 'Sign in')),
              ]),
            ),
          ),
        ),
      );
}

class Shell extends ConsumerStatefulWidget {
  final StaffRoles roles;
  const Shell({super.key, required this.roles});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final r = widget.roles;
    final pages = <(String, IconData, Widget)>[
      if (r.hub) ('Overview', Icons.dashboard_rounded, const OverviewPage()),
      if (r.hub) ('Receiving', Icons.move_to_inbox_rounded, const ReceivingPage()),
      if (r.hub) ('Scan', Icons.qr_code_scanner_rounded, const ScanPage()),
      if (r.hub) ('Stock', Icons.inventory_2_rounded, const StockPage()),
      if (r.hub) ('Pick and cut', Icons.content_cut_rounded, const OrdersPage()),
      if (r.hub) ('Rooms', Icons.ac_unit_rounded, const RoomsPage()),
      if (r.hub || r.certifier) ('Certificates', Icons.verified_rounded, const CertsPage()),
      if (r.admin) ('Applications', Icons.assignment_ind_rounded, const ApplicationsPage()),
      if (r.admin) ('Drivers', Icons.two_wheeler_rounded, const DriverApplicationsPage()),
      if (r.admin) ('Plans', Icons.workspace_premium_rounded, const PlansPage()),
      if (r.admin) ('Alerts', Icons.mark_email_unread_rounded, const OutboxPage()),
      if (r.admin) ('Memberships', Icons.card_membership_rounded, const MembershipsPage()),
      if (r.admin) ('Boreholes', Icons.water_rounded, const BoreholesPage()),
      if (r.admin) ('Security', Icons.shield_rounded, const SecurityPage()),
      if (r.vet) ('Vet cases', Icons.medical_services_rounded, const VetPage()),
    ];
    final idx = _i.clamp(0, pages.length - 1);
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: pages[idx].$3));
    return Scaffold(
      appBar: AppBar(
        title: Text('Nolifa Back Office  -  Durban hub'),
        actions: [
          Center(child: Text(_db.auth.currentUser?.email ?? '', style: const TextStyle(fontSize: 13))),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout_rounded), onPressed: _db.auth.signOut),
        ],
      ),
      body: Row(children: [
        if (wide)
          // The rail has no scrolling of its own, and there are more pages than a
          // laptop screen is tall.
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: idx,
                    onDestinationSelected: (v) => setState(() => _i = v),
                    labelType: NavigationRailLabelType.all,
                    destinations: [for (final p in pages) NavigationRailDestination(icon: Icon(p.$2), label: Text(p.$1))],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: body),
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (v) => setState(() => _i = v),
              destinations: [for (final p in pages) NavigationDestination(icon: Icon(p.$2), label: p.$1)],
            ),
    );
  }
}

/// All orders that go through the hub, newest first. Staff can read these
/// because row level security lets hub staff read orders whose route is hub.
final hubOrdersProvider = StreamProvider<List<Order>>((ref) {
  final uid = ref.watch(marketUidProvider);
  return _db.from('market_orders').stream(primaryKey: ['id']).eq('route', 'hub').map((rows) {
    final list = [for (final r in rows) orderFromJson(Map<String, dynamic>.from(r['data'] as Map), uid)];
    list.sort((a, b) => b.placed.compareTo(a.placed));
    return list;
  });
});

/// Moves a hub order on one step. The database only allows the staff steps
/// droppedOff to received and received to released.
Future<void> setHubStage(Order o, String stage) =>
    _db.rpc('set_hub_stage', params: {'p_id': o.id, 'p_stage': stage});
