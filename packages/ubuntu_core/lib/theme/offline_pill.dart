import 'package:flutter/material.dart' hide Text;
import '../supabase/offline_cache.dart';
import '../supabase/outbox.dart';
import 'app_theme.dart';

import '../tr_text.dart' show Text;
/// Wrap the app in this (MaterialApp.builder) to show a small pill at the top
/// whenever the phone has no signal. It says what still works, and from when the
/// saved data is.
class OfflineOverlay extends StatelessWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(alignment: Alignment.topCenter, child: IgnorePointer(child: OfflinePill())),
            ),
          ),
        ),
      ]);
}

class OfflinePill extends StatelessWidget {
  final SyncStatus? status;
  OfflinePill({super.key, this.status});

  static String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: OfflineOutbox.instance,
        builder: (context, waiting, _) => _pill(context, waiting),
      );

  Widget _pill(BuildContext context, int waiting) => ValueListenableBuilder<SyncState>(
        valueListenable: status ?? SyncStatus.instance,
        builder: (context, s, _) {
          // Changes still waiting show even once the signal is back, until they are sent.
          if (!s.offline && waiting == 0) return const SizedBox.shrink();
          final since = (s.asOf == null || !s.offline ? '' : ' Saved data from ${clock(s.asOf!)}.') +
              (waiting == 0 ? '' : ' $waiting ${waiting == 1 ? 'change waits' : 'changes wait'} to send.');
          return Semantics(
            liveRegion: true,
            label: (s.offline ? 'Offline.' : 'Sending.') + since,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.warn.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 15, color: Colors.black87),
                  const SizedBox(width: 6),
                  Text(s.offline ? 'Offline.$since' : 'Sending.$since',
                      style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          );
        },
      );
}
