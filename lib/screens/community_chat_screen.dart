import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/region_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

class CommunityChatScreen extends ConsumerStatefulWidget {
  const CommunityChatScreen({super.key});

  @override
  ConsumerState<CommunityChatScreen> createState() =>
      _CommunityChatScreenState();
}

class _CommunityChatScreenState extends ConsumerState<CommunityChatScreen> {
  final _composer = TextEditingController();
  bool _asAlert = false;
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final farmer = ref.read(currentFarmerProvider);
    if (text.isEmpty || farmer == null) return;

    setState(() => _sending = true);
    _composer.clear();
    try {
      await ref.read(chatServiceProvider).send(
            region: ref.read(chatRoomProvider),
            uid: farmer.uid,
            authorName: farmer.name,
            text: text,
            kind: _asAlert ? 'alert' : 'message',
          );
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _asAlert = false);
    } catch (e) {
      if (!mounted) return;
      _composer.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.danger,
          content: Text('Could not send: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(chatRoomProvider);
    final messages = ref.watch(chatStreamProvider(room));
    final me = ref.watch(currentFarmerProvider);

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              _Header(room: room),
              Expanded(
                child: messages.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: AppTheme.sprout)),
                  error: (e, _) => _Empty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Cannot reach the community',
                    body: '$e',
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _Empty(
                        icon: Icons.forum_outlined,
                        title: 'No messages yet',
                        body:
                            'Be the first to tell your area what you are seeing in the fields.',
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.s4, AppTheme.s4, AppTheme.s4, AppTheme.s2),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _Bubble(
                        message: list[i],
                        mine: list[i].uid == me?.uid,
                      ),
                    );
                  },
                ),
              ),
              _Composer(
                controller: _composer,
                asAlert: _asAlert,
                sending: _sending,
                onToggleAlert: () => setState(() => _asAlert = !_asAlert),
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final String room;
  const _Header({required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Community', style: AppTheme.title2),
                    Text('Talk to farmers near you', style: AppTheme.footnote),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s3),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s2),
              itemCount: RegionService.regions.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppTheme.s2),
              itemBuilder: (_, i) {
                final r = RegionService.regions[i];
                final selected = r.name == room;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(chatRoomProvider.notifier).state = r.name;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.s4, vertical: AppTheme.s2),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.sprout.withValues(alpha: 0.2)
                          : AppTheme.glassFill,
                      borderRadius: BorderRadius.circular(AppTheme.rChip),
                      border: Border.all(
                          color: selected
                              ? AppTheme.sprout
                              : AppTheme.glassBorderSoft),
                    ),
                    child: Center(
                      child: Text(
                        r.name,
                        style: AppTheme.footnote.copyWith(
                          color: selected
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final alert = message.kind == 'alert';
    final bg = alert
        ? AppTheme.warn.withValues(alpha: 0.18)
        : mine
            ? AppTheme.sprout.withValues(alpha: 0.2)
            : AppTheme.glassFill;
    final border = alert
        ? AppTheme.warn.withValues(alpha: 0.5)
        : mine
            ? AppTheme.sprout.withValues(alpha: 0.4)
            : AppTheme.glassBorderSoft;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: AppTheme.s3),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4, vertical: AppTheme.s3),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppTheme.rControl),
            topRight: const Radius.circular(AppTheme.rControl),
            bottomLeft: Radius.circular(mine ? AppTheme.rControl : AppTheme.s1),
            bottomRight: Radius.circular(mine ? AppTheme.s1 : AppTheme.rControl),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (alert) ...[
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppTheme.warn),
                  const SizedBox(width: AppTheme.s1),
                ],
                Text(
                  mine ? 'You' : message.authorName,
                  style: AppTheme.caption.copyWith(
                    color: alert ? AppTheme.warn : AppTheme.sprout,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppTheme.s2),
                Text(_stamp(message.createdAt), style: AppTheme.caption),
              ],
            ),
            const SizedBox(height: AppTheme.s1),
            Text(message.text, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  String _stamp(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.day}/${t.month}';
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool asAlert;
  final bool sending;
  final VoidCallback onToggleAlert;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.asAlert,
    required this.sending,
    required this.onToggleAlert,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppTheme.s4, 0, AppTheme.s4,
          MediaQuery.viewInsetsOf(context).bottom + AppTheme.s4),
      child: GlassCard(
        radius: AppTheme.rControl,
        padding: const EdgeInsets.fromLTRB(
            AppTheme.s3, AppTheme.s2, AppTheme.s2, AppTheme.s2),
        child: Column(
          children: [
            if (asAlert)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: AppTheme.s2, top: AppTheme.s1),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 15, color: AppTheme.warn),
                    const SizedBox(width: AppTheme.s2),
                    Text('Posting as a disease alert',
                        style:
                            AppTheme.caption.copyWith(color: AppTheme.warn)),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    asAlert
                        ? Icons.warning_amber_rounded
                        : Icons.add_alert_outlined,
                    size: 21,
                    color: asAlert ? AppTheme.warn : AppTheme.textTertiary,
                  ),
                  onPressed: onToggleAlert,
                  tooltip: 'Flag as disease alert',
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppTheme.sprout,
                    decoration: InputDecoration(
                      hintText: 'Share what you are seeing...',
                      hintStyle: AppTheme.subhead,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: AppTheme.s3),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.s2),
                GestureDetector(
                  onTap: sending ? null : onSend,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: asAlert ? AppTheme.warn : AppTheme.sprout,
                    ),
                    child: sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF07150F)),
                          )
                        : const Icon(Icons.arrow_upward_rounded,
                            size: 20, color: Color(0xFF07150F)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Empty({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.s4),
            Text(title, style: AppTheme.title3, textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.s2),
            Text(body, style: AppTheme.footnote, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
