import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'trust_screens.dart' show ScreenFrame;

/// A short, plain note that something here is simulated in the prototype.
/// Shown where a judge or a farmer might otherwise assume it is real.
class PrototypeNotice extends StatelessWidget {
  final String text;
  const PrototypeNotice(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppTheme.s3),
        decoration: BoxDecoration(
          color: AppTheme.warn.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.warn.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.science_rounded, size: 18, color: AppTheme.warn),
          const SizedBox(width: AppTheme.s2),
          Expanded(child: Text(text, style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary))),
        ]),
      );
}

/// Which parts of Nolifa are free, which cost money, and why. The essentials
/// for staying safe are free for everyone. Only selling carries a fee.
class FreeVsPaidCard extends StatelessWidget {
  const FreeVsPaidCard({super.key});

  Widget _row(String icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
              Text(sub, style: AppTheme.caption),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Free for everyone, always', style: AppTheme.headline.copyWith(color: AppTheme.sprout)),
          const SizedBox(height: AppTheme.s2),
          _row('🔬', 'Crop scanner and cattle symptom checker', 'The tools that protect a farm never cost anything.'),
          _row('📡', 'Water radar, forecasts and community voice', 'Nobody pays to be warned or to ask for help.'),
          _row('🚨', 'Outbreak map, alerts and the community', 'Reporting and reading are free.'),
          _row('🛒', 'Buying food and water', 'Customers pay a small service fee, only on an order.'),
          const Divider(height: AppTheme.s5),
          Text('Paid: selling on Nolifa Drop', style: AppTheme.headline.copyWith(color: AppTheme.warn)),
          const SizedBox(height: AppTheme.s2),
          Text(
              'A plan from R49 a month covers payments in escrow, delivery matching, disputes and support. '
              'You also pay a commission only when a sale completes, so a farm that sells nothing owes only the plan. '
              'Starter pays for itself with a few baskets a month. These prices are a starting point we will test with farmers before launch.',
              style: AppTheme.footnote),
        ]),
      );
}

/// What works with no signal and what needs a connection or another person.
class OfflineGuideScreen extends StatelessWidget {
  const OfflineGuideScreen({super.key});

  Widget _list(String title, String sub, Color color, List<String> items) => GlassCard(
        tint: color.withValues(alpha: 0.10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTheme.headline.copyWith(color: color)),
          Text(sub, style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s2),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: AppTheme.callout.copyWith(color: color)),
                Expanded(child: Text(i, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary))),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => ScreenFrame(title: 'Offline and online', children: [
        Text(
            'Nolifa is built for patchy signal. Some things work with none. Others need a connection, or another person.',
            style: AppTheme.callout),
        _list('Works with no signal', 'Runs on your phone', AppTheme.ok, const [
          'Leaf scanner (the model is on the phone)',
          'Cattle symptom checker and herd register',
          'Crop health tracker and sprinkler plans',
          'Everything you already loaded: your orders, wallet, saved scans and last water reading',
          'Taking proof photos. They send when you are back online',
        ]),
        _list('Needs a connection', 'Reaches other people or services', AppTheme.warn, const [
          'Placing or paying for an order, and seeing a farm\'s live stock',
          'Fresh water readings, the community vote and the provider\'s reply',
          'Outbreak reports reaching neighbours, and the community feed',
          'Maps, routes and the driver\'s navigation',
          'Notifications from other people',
        ]),
        _list('Needs another person', 'Nothing happens until they act', AppTheme.danger, const [
          'A delivery: a driver, or the farm, has to accept and bring it',
          'Water trucks: the provider (or a farm supplier) has to answer',
          'Outbreak confirmation: neighbours confirm before a report goes public',
          'Inspection: an inspector has to visit',
        ]),
        const PrototypeNotice(
            'In this prototype the apps keep data on the phone, so two phones do not see each other until the shared backend is switched on.'),
      ]);
}

/// The honest list of what is simulated, for the Trust and Safety page.
class PrototypeLimitsBlock extends StatelessWidget {
  const PrototypeLimitsBlock({super.key});

  @override
  Widget build(BuildContext context) => GlassCard(
        tint: AppTheme.warn.withValues(alpha: 0.10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🧪', style: TextStyle(fontSize: 22)),
            const SizedBox(width: AppTheme.s2),
            Expanded(child: Text('What is simulated in this prototype', style: AppTheme.headline)),
          ]),
          const SizedBox(height: AppTheme.s2),
          for (final t in const [
            'Payments and escrow. No real money moves. FNB would hold the funds in production.',
            'Identity, bank and Home Affairs checks. Each step is a demo button.',
            'Farm and land inspection results, and vet and mediator decisions.',
            'Water provider readings and replies, and neighbour and driver activity in demo mode.',
            'Sharing between phones. It needs the shared backend, which is switched off.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: AppTheme.callout),
                Expanded(child: Text(t, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary))),
              ]),
            ),
          const SizedBox(height: AppTheme.s2),
          Text('What is real: the fee and escrow rules, the PIN, disputes logic, the forecasts, the AI scans and the on-phone storage.',
              style: AppTheme.footnote),
        ]),
      );
}
