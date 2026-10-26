import 'package:flutter/material.dart' hide Text;
import '../edition.dart';
import '../theme/app_theme.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// What the app is, what it does, what works without signal, and who built it.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _deep = Color(0xFF1B4332);
  static const _green = Color(0xFF2D6A4F);

  @override
  Widget build(BuildContext context) {
    final grow = AppEdition.isGrow;
    return Scaffold(
      backgroundColor: AppTheme.pageGreen,
      appBar: AppBar(
        backgroundColor: _deep,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Center(
              child: Column(children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.eco_rounded, color: Colors.white, size: 50),
                ),
                const SizedBox(height: 16),
                Text(AppEdition.name,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                Text('Catch it early. Keep your community fed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
                const SizedBox(height: 6),
                Text('Version 1.0.0', style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
              ]),
            ),
            const SizedBox(height: 28),

            _Section(
              title: 'What ${AppEdition.name} does',
              body: grow
                  ? 'Nolifa Grow protects farms. It catches crop and livestock disease early, warns the farms around you, '
                      'tracks your water, and helps you sell what you grow to people nearby.'
                  : 'Nolifa Grow protects farming communities. It catches disease early, warns everyone nearby, and keeps food '
                      'moving from local farms to local families. Farmers, households and drivers each get the part of the app they use.',
            ),
            const SizedBox(height: 16),

            _Section(title: 'In the app', children: [
              const _Point(Icons.health_and_safety_rounded, 'AI diagnosis',
                  'Photograph a sick plant or tick an animal\'s symptoms. You get the disease and what to do, in English or isiZulu.'),
              const _Point(Icons.map_rounded, 'Live outbreak map',
                  'Reports show by area, never at a farm. Nearby farms are alerted once 2 verified farms confirm, and a vet or extension officer can verify.'),
              const _Point(Icons.water_drop_rounded, 'Water alerts',
                  'Real dam levels from the Department of Water and Sanitation, how long supply will last, and help requests neighbours vote on.'),
              const _Point(Icons.wb_cloudy_rounded, '7-day farm forecast',
                  'Real weather turned into warnings for frost, heat, heavy rain and fungus, with what to do.'),
              _Point(Icons.storefront_rounded, grow ? 'Sell nearby' : 'Marketplace and delivery',
                  'Farmers sell straight to their community. Money is held safely until the buyer gives the delivery PIN.'),
            ]),
            const SizedBox(height: 16),

            _Section(
              title: 'Works without signal',
              intro: 'Farms are where the signal is weakest, so the parts that keep people safe keep working offline.',
              children: const [
                _Point(Icons.document_scanner_rounded, 'Plant check',
                    'An AI model on the phone checks tomato and potato leaves for early blight, late blight and leaf miner. With signal, the full check covers hundreds of plants.'),
                _Point(Icons.pets_rounded, 'Animal symptom check',
                    'The symptom checker and the disease guide are stored on the phone.'),
                _Point(Icons.cloud_off_rounded, 'Last saved map and data',
                    'The outbreak map, dam levels, road alerts, orders and the weather forecast show the last copy saved on the phone.'),
                _Point(Icons.outbox_rounded, 'Reports wait and send',
                    'Outbreak reports, confirmations, water votes and stock changes wait on the phone and send by themselves when signal returns.'),
              ],
              outro: 'Payments, deliveries and vet consults need signal, because the server must check them as they happen.',
            ),
            const SizedBox(height: 16),

            _Section(
              title: 'Built by',
              body: 'Nolifa Technologies (Pty) Ltd, a South African software company in Durban, KwaZulu-Natal.\n\n'
                  'Mpumelelo Mthethwa, Nhlanhla Mkhize, Sambulo Sithole and Atticus Mzuzwana.',
            ),
            const SizedBox(height: 16),

            // Disclaimer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.glassFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('A guide, not a vet',
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Diagnoses are AI-generated and meant as a guide. For serious or fast-spreading illness, and for '
                  'controlled animal diseases such as foot-and-mouth, contact your vet, the state vet or an extension officer.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Contact
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(16)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 6),
                Text('Feedback, partnerships or support:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                SizedBox(height: 4),
                Text('github.com/MpumeleloM03/Nolifa-Grow', style: TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 24),

            Center(
              child: Text('© 2026 Nolifa Technologies (Pty) Ltd. All rights reserved.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? body;
  final String? intro;
  final String? outro;
  final List<Widget> children;
  const _Section({required this.title, this.body, this.intro, this.outro, this.children = const []});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.glassFill, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          if (body != null) ...[
            const SizedBox(height: 10),
            Text(body!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
          ],
          if (intro != null) ...[
            const SizedBox(height: 8),
            Text(intro!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
          ],
          if (children.isNotEmpty) const SizedBox(height: 12),
          ...children,
          if (outro != null) ...[
            const SizedBox(height: 4),
            Text(outro!, style: TextStyle(color: AppTheme.textTertiary, fontSize: 12, height: 1.5)),
          ],
        ]),
      );
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Point(this.icon, this.title, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.sprout.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.sprout),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(text, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45)),
            ]),
          ),
        ]),
      );
}
