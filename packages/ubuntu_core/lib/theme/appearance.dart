import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'glass.dart';

/// How the app picks its palette: follow the phone, or pin light or dark.
enum AppearanceMode { system, light, dark }

/// Stores the user's choice and tells [AppearanceScope] when it changes.
class AppearanceController extends ChangeNotifier {
  AppearanceController._();
  static final AppearanceController instance = AppearanceController._();

  static const _key = 'appearance.mode';
  AppearanceMode _mode = AppearanceMode.system;
  AppearanceMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
        AppearanceMode.system => ThemeMode.system,
        AppearanceMode.light => ThemeMode.light,
        AppearanceMode.dark => ThemeMode.dark,
      };

  /// Reads the saved choice. Call before `runApp` so the first frame is right.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      _mode = AppearanceMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => AppearanceMode.system,
      );
    } catch (_) {
      _mode = AppearanceMode.system;
    }
    AppTheme.isLight = resolveLight();
  }

  Future<void> set(AppearanceMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  /// Whether the light palette applies right now, given the choice and the phone.
  bool resolveLight() => switch (_mode) {
        AppearanceMode.light => true,
        AppearanceMode.dark => false,
        AppearanceMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.light,
      };
}

/// Wrap the `MaterialApp` in this. It flips [AppTheme.isLight] when the choice
/// or the phone setting changes, then rebuilds every element so the palette
/// getters (which are read at build time) pick up the new values.
class AppearanceScope extends StatefulWidget {
  final Widget Function(BuildContext context, ThemeData light, ThemeData dark,
      ThemeMode mode) builder;

  const AppearanceScope({super.key, required this.builder});

  /// Status-bar icons that stay readable on the current background.
  static SystemUiOverlayStyle get overlay =>
      (AppTheme.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
          .copyWith(statusBarColor: Colors.transparent);

  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends State<AppearanceScope>
    with WidgetsBindingObserver {
  final _controller = AppearanceController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_sync);
    AppTheme.isLight = _controller.resolveLight();
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _sync();

  void _sync() {
    final light = _controller.resolveLight();
    if (light == AppTheme.isLight) {
      if (mounted) setState(() {});
      return;
    }
    AppTheme.isLight = light;
    if (!mounted) return;
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        AppTheme.buildLight(),
        AppTheme.build(),
        _controller.themeMode,
      );
}

/// Settings row: System / Light / Dark.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: AppTheme.headline),
            const SizedBox(height: AppTheme.s1),
            Text('System follows your phone setting.', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s3),
            Row(
              children: [
                for (final m in AppearanceMode.values) ...[
                  Expanded(
                    child: _Choice(
                      mode: m,
                      selected: controller.mode == m,
                      onTap: () => controller.set(m),
                    ),
                  ),
                  if (m != AppearanceMode.values.last)
                    const SizedBox(width: AppTheme.s2),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final AppearanceMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _Choice(
      {required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (mode) {
      AppearanceMode.system => ('System', Icons.smartphone_rounded),
      AppearanceMode.light => ('Light', Icons.light_mode_rounded),
      AppearanceMode.dark => ('Dark', Icons.dark_mode_rounded),
    };
    final radius = BorderRadius.circular(AppTheme.rControl);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label appearance',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.s3),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: selected
                  ? AppTheme.sprout.withValues(alpha: 0.18)
                  : AppTheme.glassFill,
              border: Border.all(
                color: selected ? AppTheme.sprout : AppTheme.glassBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 20,
                    color: selected ? AppTheme.sprout : AppTheme.textSecondary),
                const SizedBox(height: AppTheme.s1),
                Text(label,
                    style: AppTheme.footnote.copyWith(
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
