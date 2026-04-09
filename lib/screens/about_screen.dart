import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B4332),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'About',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.eco,
                color: Colors.white,
                size: 56,
              ),
            ),

            const SizedBox(height: 24),

            // App name
            const Text(
              'Nolifa Grow',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Every plant has a story. We help you hear it.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white60,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            const Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white38,
              ),
            ),

            const SizedBox(height: 40),

            // What we do
            _buildSection(
              'What Nolifa Grow Does',
              'Nolifa Grow is an AI-powered plant disease diagnostic tool built specifically for Southern African farmers, gardeners, and agricultural students.\n\nPoint your camera at any sick plant and get an instant diagnosis in plain language — what is wrong, how serious it is, and exactly what to do about it. No agricultural knowledge required.',
            ),

            const SizedBox(height: 24),

            // How it works
            _buildSection(
              'How It Works',
              'When you are connected to the internet, Nolifa Grow uses advanced cloud AI to analyse your plant image and identify diseases with high accuracy across hundreds of plant conditions.\n\nWhen you are offline, the app switches automatically to an on-device AI model so you always get a diagnosis even in a field with no signal.',
            ),

            const SizedBox(height: 24),

            // Disclaimer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white60,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Important Disclaimer',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Nolifa Grow provides AI-generated diagnoses intended as a guide only. Results should not replace professional agricultural advice. Always consult a qualified agricultural expert or extension officer for serious crop concerns or before making significant treatment decisions.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Built by
            _buildSection(
              'Built By',
              'Nolifa Grow was built by Mpumelelo Mthethwa, an Information Technology student and solo developer.\n\nBuilt specifically for Southern African farmers and gardeners who need fast, reliable answers about their plants, no agricultural knowledge required.',
            ),

            const SizedBox(height: 24),

            // Contact
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'For feedback, partnerships, or support:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'github.com/MpumeleloM03',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ✅ COPYRIGHT FOOTER
            const Text(
              '© 2025 Nolifa Technologies (Pty) Ltd',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white24,
                fontSize: 11,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}