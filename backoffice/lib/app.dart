import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'pages/certs_page.dart';
import 'pages/orders_page.dart';
import 'pages/overview_page.dart';
import 'pages/receiving_page.dart';
import 'pages/rooms_page.dart';
import 'pages/scan_page.dart';
import 'pages/stock_page.dart';

final authUserProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

/// Wires the shared package into the staff member's own sign-in and the shared
/// Firestore. No demo content, ever.
List<Override> backOfficeOverrides() => [
      ...liveOverrides(() => true),
      marketUidProvider.overrideWith((ref) => ref.watch(authUserProvider).valueOrNull?.uid ?? 'guest'),
      marketNameProvider.overrideWith((ref) {
        final u = ref.watch(authUserProvider).valueOrNull;
        final n = (u?.displayName ?? u?.email ?? 'Staff').split('@').first;
        return n.isEmpty ? 'Staff' : n;
      }),
      marketRepositoryProvider.overrideWith((ref) => FirestoreMarketRepository()),
      waterRepositoryProvider.overrideWith((ref) => FirestoreWaterRepository()),
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
      error: (e, _) => Scaffold(body: Center(child: Text('Could not start: $e'))),
      data: (u) => u == null ? const LoginPage() : const _Access(),
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
      error: (e, _) => Scaffold(body: Center(child: Text('Could not check access: $e'))),
      data: (r) => (r.hub || r.certifier)
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
                          'You are signed in as ${FirebaseAuth.instance.currentUser?.email}. A Nolifa admin has to add you as warehouse staff or a certifier before you can use the back office. '
                          'Send them this ID: ${FirebaseAuth.instance.currentUser?.uid}',
                          style: AppTheme.callout),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: FirebaseAuth.instance.signOut, child: const Text('Sign out')),
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found'
          ? 'Check your email and password.'
          : 'Could not sign in (${e.code}).');
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
      ('Certificates', Icons.verified_rounded, const CertsPage()),
    ];
    final idx = _i.clamp(0, pages.length - 1);
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: pages[idx].$3));
    return Scaffold(
      appBar: AppBar(
        title: Text('Nolifa Back Office  -  Durban hub'),
        actions: [
          Center(child: Text(FirebaseAuth.instance.currentUser?.email ?? '', style: const TextStyle(fontSize: 13))),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout_rounded), onPressed: FirebaseAuth.instance.signOut),
        ],
      ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            selectedIndex: idx,
            onDestinationSelected: (v) => setState(() => _i = v),
            labelType: NavigationRailLabelType.all,
            destinations: [for (final p in pages) NavigationRailDestination(icon: Icon(p.$2), label: Text(p.$1))],
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
/// because the rules allow hub staff to read orders whose route is hub.
final hubOrdersProvider = StreamProvider<List<Order>>((ref) {
  final uid = ref.watch(marketUidProvider);
  return FirebaseFirestore.instance.collection('marketOrders').where('route', isEqualTo: 'hub').snapshots().map((q) {
    final list = [for (final d in q.docs) orderFromJson(d.data(), uid)];
    list.sort((a, b) => b.placed.compareTo(a.placed));
    return list;
  });
});

/// Moves a hub order on one step. The rules only allow the staff steps
/// droppedOff to received and received to released.
Future<void> setHubStage(Order o, String stage) =>
    FirebaseFirestore.instance.collection('marketOrders').doc(o.id).update({'hubStage': stage, 'rev': o.rev + 1});
