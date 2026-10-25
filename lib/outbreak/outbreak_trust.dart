import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ubuntu_core/ubuntu_core.dart'
    show KycRole, MarketState, Pill, ReportCase, ReportStage, SupabaseBoot, VerifyScreen, marketProvider;
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// How far an outbreak report has got. A report shows on the map at once as
/// unconfirmed. Two verified farms confirming it make it confirmed, and only
/// then are nearby farms alerted. A vet or an extension officer can verify it.
enum Trust { unconfirmed, confirmed, verified }

/// How many farms must confirm a report before the area is alerted. The
/// server's confirm_case uses the same number.
const kConfirmationsNeeded = 2;

extension TrustX on Trust {
  String get label => switch (this) {
        Trust.unconfirmed => 'Unconfirmed',
        Trust.confirmed => 'Farms confirmed',
        Trust.verified => 'Verified',
      };

  Color get color => switch (this) {
        Trust.unconfirmed => AppTheme.textSecondary,
        Trust.confirmed => AppTheme.warn,
        Trust.verified => AppTheme.sprout,
      };

  IconData get icon => switch (this) {
        Trust.unconfirmed => Icons.help_outline_rounded,
        Trust.confirmed => Icons.groups_rounded,
        Trust.verified => Icons.verified_rounded,
      };

  /// Only confirmed or verified reports raise alarms and heat the map fully.
  bool get alerts => this != Trust.unconfirmed;
}

/// Where a case stands, or null when it was rejected and should leave the map.
Trust? trustOfCase(ReportCase? c) {
  if (c == null) return Trust.unconfirmed;
  return switch (c.stage) {
    ReportStage.rejected => null,
    ReportStage.vetVerified => Trust.verified,
    ReportStage.corroborated => Trust.confirmed,
    _ => Trust.unconfirmed,
  };
}

Map<String, ReportCase> casesById(MarketState s) => {for (final c in s.cases) c.id: c};

/// 'vet' or 'officer' when this person may verify or reject outbreak reports,
/// otherwise null. The server decides; the app only shows the buttons.
final caseVerifierProvider = FutureProvider<String?>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  if (!SupabaseBoot.ready) return null;
  try {
    final role = await SupabaseBoot.client.rpc('case_verifier_role');
    return role is String ? role : null;
  } catch (_) {
    return null;
  }
});

/// Records a vet's or officer's decision. Returns an error to show, or null.
Future<String?> verifyCase(WidgetRef ref, String id, bool ok) async {
  final role = ref.read(caseVerifierProvider).valueOrNull ?? 'officer';
  ref.read(marketProvider.notifier).applyVerification(id, ok, role);
  if (!SupabaseBoot.ready) return null;
  try {
    await SupabaseBoot.client.rpc('verify_case', params: {'p_id': id, 'p_ok': ok});
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  } catch (_) {
    return 'Could not save that. Check your connection and try again.';
  }
}

/// The trust badge plus what this person can do about a report: confirm it
/// ("I see this too"), or verify or reject it if they are a vet or officer.
class CaseTrustRow extends ConsumerWidget {
  final String? caseId;
  final Trust trust;
  const CaseTrustRow({super.key, required this.caseId, required this.trust});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caseId == null
        ? null
        : ref.watch(marketProvider.select((s) => s.cases.where((x) => x.id == caseId).firstOrNull));
    final verifier = ref.watch(caseVerifierProvider).valueOrNull != null;
    final t = c == null ? trust : (trustOfCase(c) ?? trust);
    final n = c?.confirmations ?? 0;

    final status = switch (t) {
      Trust.unconfirmed => c == null
          ? 'Not yet confirmed by other farms.'
          : '$n of $kConfirmationsNeeded farms confirmed. Nearby farms are alerted once $kConfirmationsNeeded confirm.',
      Trust.confirmed => 'Confirmed by ${c == null ? 'neighbouring' : n} farms. Nearby farms have been alerted.',
      Trust.verified => c == null ? 'Verified by a vet or extension officer.' : 'Verified by ${c.verifierLabel}.',
    };

    final messenger = ScaffoldMessenger.of(context);
    void snack(String msg) =>
        messenger.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

    final canConfirm = c != null && !c.mine && t == Trust.unconfirmed && !c.confirmedBy.contains(ref.read(currentUserProvider)?.uid);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Pill(t.label, color: t.color, icon: t.icon),
        const SizedBox(width: AppTheme.s2),
        Expanded(child: Text(status, style: AppTheme.caption)),
      ]),
      if (canConfirm || (verifier && c != null && t != Trust.verified)) ...[
        const SizedBox(height: AppTheme.s2),
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          if (canConfirm && c != null)
            _Action('I see this too', Icons.visibility_rounded, AppTheme.livestockAccent, () {
              HapticFeedback.lightImpact();
              if (!ref.read(marketProvider.notifier).confirmCase(c.id)) {
                messenger.showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: const Text('Only verified farmers can confirm an outbreak, so reports cannot be faked.'),
                  action: SnackBarAction(
                    label: 'Verify',
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const VerifyScreen(role: KycRole.farmer))),
                  ),
                ));
              } else {
                snack('Thanks. Your confirmation was added.');
              }
            }),
          if (verifier && c != null && t != Trust.verified) ...[
            _Action('Verify', Icons.verified_rounded, AppTheme.sprout, () async {
              HapticFeedback.mediumImpact();
              final err = await verifyCase(ref, c.id, true);
              snack(err ?? 'Verified. Nearby farms are alerted.');
            }),
            _Action('Not this', Icons.block_rounded, AppTheme.danger, () async {
              HapticFeedback.mediumImpact();
              final err = await verifyCase(ref, c.id, false);
              snack(err ?? 'Rejected. It has been taken off the map.');
            }),
          ],
        ]),
      ],
    ]);
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Action(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Pill(label, color: color, icon: icon),
      );
}

/// Verify and reject buttons under a case card, shown only to vets and
/// extension officers, and only while the case still needs a decision.
class CaseVerifyButtons extends ConsumerWidget {
  final ReportCase c;
  const CaseVerifyButtons(this.c, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(caseVerifierProvider).valueOrNull;
    if (role == null || c.stage == ReportStage.vetVerified || c.stage == ReportStage.rejected) {
      return const SizedBox.shrink();
    }
    final messenger = ScaffoldMessenger.of(context);
    void snack(String msg) =>
        messenger.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.s2),
      child: Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(role == 'vet' ? 'As a vet:' : 'As an extension officer:', style: AppTheme.caption),
        _Action('Verify', Icons.verified_rounded, AppTheme.sprout, () async {
          HapticFeedback.mediumImpact();
          final err = await verifyCase(ref, c.id, true);
          snack(err ?? 'Verified. Nearby farms are alerted.');
        }),
        _Action('Not this', Icons.block_rounded, AppTheme.danger, () async {
          HapticFeedback.mediumImpact();
          final err = await verifyCase(ref, c.id, false);
          snack(err ?? 'Rejected. It has been taken off the map.');
        }),
      ]),
    );
  }
}
