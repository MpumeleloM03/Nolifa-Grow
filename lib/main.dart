import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'services/image_service.dart';
import 'services/inference_service.dart';
import 'services/plant_id_service.dart';
import 'services/history_service.dart';
import 'screens/result_screen.dart';
import 'screens/about_screen.dart';
import 'screens/history_screen.dart';
import 'screens/map_screen.dart';
import 'models/diagnosis_record.dart';
import 'models/disease_info.dart';
import 'models/outbreak_report.dart';
import 'screens/auth/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/outbreak_service.dart';
import 'services/region_service.dart';
import 'services/firebase_boot.dart';
import 'theme/app_theme.dart';
import 'theme/glass.dart';
import 'utils/language_provider.dart';
import 'utils/translations.dart';
import 'widgets/language_toggle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBoot.init();
  runApp(
    const ProviderScope(
      child: NolifaGrowApp(),
    ),
  );
}

class NolifaGrowApp extends ConsumerWidget {
  const NolifaGrowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Nolifa Grow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const AuthGate(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ImageService _imageService = ImageService();
  final InferenceService _inferenceService = InferenceService();
  final PlantIdService _plantIdService = PlantIdService();
  final HistoryService _historyService = HistoryService();
  File? _selectedImage;
  bool _isLoading = false;
  bool _modelLoaded = false;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    await _inferenceService.loadModel();
    setState(() {
      _modelLoaded = true;
    });
  }

  Future<void> _diagnoseImage(File imageFile) async {
    setState(() {
      _isLoading = true;
    });

    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.mobile);

    Map<String, dynamic>? result;

    if (_isOnline) {
      result = await _plantIdService.diagnose(imageFile);
    }

    if (result == null) {
      result = await _inferenceService.diagnose(imageFile);
      if (result != null) {
        result['offlineMode'] = true;
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (result != null && mounted) {
      final info = DiseaseDatabase.getInfo(result['label'] ?? 'Unknown');
      final record = DiagnosisRecord(
        id: const Uuid().v4(),
        label: result['label'] ?? 'Unknown',
        plainName: info.plainName,
        confidence: result['confidence'] ?? '0',
        imagePath: imageFile.path,
        date: DateTime.now(),
        offlineMode: result['offlineMode'] ?? false,
      );
      await _historyService.saveRecord(record);
      _contributeToMap(result['label'] ?? 'Unknown', info.severityColor);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            image: imageFile,
            label: result!['label'] ?? 'Unknown',
            confidence: result['confidence'] ?? '0',
            offlineMode: result['offlineMode'] ?? false,
          ),
        ),
      );
    }
  }

  /// Adds this diagnosis to the community outbreak map.
  ///
  /// The point is placed inside the farmer's region rather than at their
  /// coordinates, so the map shows where disease is active without exposing
  /// whose farm it came from. Failures here are silent — a farmer waiting on a
  /// diagnosis should never be blocked by a map write.
  void _contributeToMap(String disease, String severityColor) {
    final region = ref.read(userProfileProvider).valueOrNull?.region;
    if (region == null) return;
    final centre = RegionService.findByName(region)?.center;
    if (centre == null) return;

    ref.read(outbreakServiceProvider).report(
          disease: disease,
          severity: severityColor,
          kind: OutbreakKind.plant,
          exactLocation: RegionService.jitter(centre, disease + region),
          region: region,
        );
  }

  void _showImageOptions(String lang) {
    final t = AppTranslations.get;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: Color(0xFF2D6A4F),
              ),
              title: Text(t('take_photo', lang)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imageService.pickFromCamera();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                  await _diagnoseImage(image);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFF2D6A4F),
              ),
              title: Text(t('choose_gallery', lang)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imageService.pickFromGallery();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                  await _diagnoseImage(image);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inferenceService.dispose();
    super.dispose();
  }

  Widget _buildStep(
      String number, String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            icon,
            color: Colors.white38,
            size: 20,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final t = AppTranslations.get;

    return Scaffold(
      backgroundColor: AppTheme.forestDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GhostButton(
                    label: 'Home',
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('app_name', lang),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t('tagline', lang),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t('catchphrase', lang),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white38,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const LanguageToggle(),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (value) {
                            Widget page;
                            switch (value) {
                              case 'history':
                                page = const HistoryScreen();
                                break;
                              case 'map':
                                page = const MapScreen();
                                break;
                              case 'about':
                                page = const AboutScreen();
                                break;
                              default:
                                return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => page),
                            );
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'history',
                              child: Text('History'),
                            ),
                            const PopupMenuItem(
                              value: 'map',
                              child: Text('Map'),
                            ),
                            const PopupMenuItem(
                              value: 'about',
                              child: Text('About'),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: _modelLoaded && !_isLoading
                      ? () => _showImageOptions(lang)
                      : null,
                  child: Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: _isLoading
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                t('analysing', lang),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : _selectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Colors.white54,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    t('tap_to_scan', lang),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t('camera_or_gallery', lang),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  t('how_it_works', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStep(
                  '1',
                  t('step1_title', lang),
                  t('step1_sub', lang),
                  Icons.camera_alt,
                ),
                const SizedBox(height: 12),
                _buildStep(
                  '2',
                  t('step2_title', lang),
                  t('step2_sub', lang),
                  Icons.search,
                ),
                const SizedBox(height: 12),
                _buildStep(
                  '3',
                  t('step3_title', lang),
                  t('step3_sub', lang),
                  Icons.healing,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}