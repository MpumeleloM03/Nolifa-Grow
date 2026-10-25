import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:ubuntu_core/ubuntu_core.dart' show FarmLogo, FarmBrands, SupabaseBoot, farmBanner, friendlyError;
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// An approved farm changes its logo or store picture. They show in Nolifa Drop
/// as soon as they are saved.
class FarmPicturesScreen extends StatefulWidget {
  final String farmName;
  const FarmPicturesScreen({super.key, required this.farmName});

  @override
  State<FarmPicturesScreen> createState() => _FarmPicturesScreenState();
}

class _FarmPicturesScreenState extends State<FarmPicturesScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _change(bool logo) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: logo ? 800 : 1800);
    if (x == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final db = SupabaseBoot.client;
      final path = '${db.auth.currentUser!.id}/${logo ? 'logo' : 'banner'}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage.from('farm-brand').upload(path, File(x.path), fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await db.rpc('set_farm_brand', params: {if (logo) 'p_logo': path else 'p_banner': path});
      _message = logo ? 'Logo saved. Buyers see it now.' : 'Store picture saved. Buyers see it now.';
    } catch (e) {
      _message = friendlyError(e, doing: 'save that picture');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Farm pictures'), backgroundColor: Colors.transparent),
      body: AppBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: FarmBrands.instance,
            builder: (context, _) {
              final banner = farmBanner(widget.farmName);
              return ListView(padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10), children: [
                Text('This is how buyers in Nolifa Drop see ${widget.farmName}.', style: AppTheme.callout),
                const SizedBox(height: AppTheme.s4),
                GlassCard(
                  child: Row(children: [
                    FarmLogo(name: widget.farmName, emoji: '🌱', size: 64),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(child: Text('Logo', style: AppTheme.headline)),
                    GhostButton(label: 'Change', onPressed: _busy ? null : () => _change(true)),
                  ]),
                ),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (banner != null)
                      ClipRRect(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                        child: SizedBox(height: 140, width: double.infinity, child: Image(image: banner, fit: BoxFit.cover)),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.s4),
                      child: Row(children: [
                        Expanded(child: Text('Store picture', style: AppTheme.headline)),
                        GhostButton(label: banner == null ? 'Choose' : 'Change', onPressed: _busy ? null : () => _change(false)),
                      ]),
                    ),
                  ]),
                ),
                if (_message != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s3), child: Text(_message!, style: AppTheme.footnote)),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
