import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');
  await CalendarNotificationService.initialize();
  runApp(const MirrorMoodApp());
}

// ============================================================
// UTILIDADES DE COLOR
// ============================================================

int colorToInt(Color color) => color.toARGB32();

int colorRed(Color color) => (color.toARGB32() >> 16) & 0xFF;

int colorGreen(Color color) => (color.toARGB32() >> 8) & 0xFF;

int colorBlue(Color color) => color.toARGB32() & 0xFF;

// ============================================================
// APP PRINCIPAL
// ============================================================

class MirrorMoodApp extends StatefulWidget {
  const MirrorMoodApp({super.key});

  @override
  State<MirrorMoodApp> createState() => _MirrorMoodAppState();
}

class _MirrorMoodAppState extends State<MirrorMoodApp> {
  Color backgroundColor = const Color(0xFF0D0D12);
  Color accentColor = const Color(0xFF8B5CF6);
  Color cardColor = const Color(0xFF17171F);

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();

    final savedBackground = prefs.getInt('backgroundColor');
    final savedAccent = prefs.getInt('accentColor');
    final savedCard = prefs.getInt('cardColor');

    if (!mounted) return;

    setState(() {
      if (savedBackground != null) {
        backgroundColor = Color(savedBackground);
      }
      if (savedAccent != null) {
        accentColor = Color(savedAccent);
      }
      if (savedCard != null) {
        cardColor = Color(savedCard);
      }
    });
  }

  Future<void> updateAppearance({
    Color? background,
    Color? accent,
    Color? card,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (background != null) {
      await prefs.setInt('backgroundColor', colorToInt(background));
    }
    if (accent != null) {
      await prefs.setInt('accentColor', colorToInt(accent));
    }
    if (card != null) {
      await prefs.setInt('cardColor', colorToInt(card));
    }

    if (!mounted) return;

    setState(() {
      if (background != null) backgroundColor = background;
      if (accent != null) accentColor = accent;
      if (card != null) cardColor = card;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MirrorMood',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          color: cardColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundColor,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: HomePage(
        onOpenSettings: (homeContext) {
          Navigator.push(
            homeContext,
            MaterialPageRoute<void>(
              builder: (_) => SettingsPage(
                backgroundColor: backgroundColor,
                accentColor: accentColor,
                cardColor: cardColor,
                onAppearanceChanged: updateAppearance,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatefulWidget {
  final void Function(BuildContext context) onOpenSettings;

  const HomePage({
    super.key,
    required this.onOpenSettings,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? selectedMood;

  final List<Map<String, String>> clothes = [];

  WeatherData? weather;
  bool loadingWeather = true;

  final List<String> motivationalPhrases = [
    'Hoy puede ser un gran día. ✨',
    'Tu estilo también es una forma de expresarte.',
    'Confía en ti y disfruta tu día. 💜',
    'No necesitas ser perfecto para verte increíble.',
    'Tu mejor outfit empieza con confianza.',
  ];

  late String dailyPhrase;

  @override
  void initState() {
    super.initState();

    final random = Random();
    dailyPhrase =
        motivationalPhrases[random.nextInt(motivationalPhrases.length)];

    _loadSavedData();
    _loadWeather();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedMood = prefs.getString('selectedMood');
    final savedClothes = prefs.getString('clothes');

    if (!mounted) return;

    setState(() {
      selectedMood = savedMood;

      if (savedClothes != null) {
        try {
          final decoded = jsonDecode(savedClothes);

          if (decoded is List) {
            clothes.clear();

            for (final item in decoded) {
              if (item is Map) {
                clothes.add(
                  Map<String, String>.from(
                    item.map(
                      (key, value) => MapEntry(
                        key.toString(),
                        value.toString(),
                      ),
                    ),
                  ),
                );
              }
            }
          }
        } catch (_) {
          clothes.clear();
        }
      }
    });
  }

  Future<void> _saveClothes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('clothes', jsonEncode(clothes));
  }

  Future<void> _loadWeather() async {
    if (mounted) {
      setState(() => loadingWeather = true);
    }

    final result = await WeatherService.getWeather();

    if (!mounted) return;

    setState(() {
      weather = result;
      loadingWeather = false;
    });
  }

  Future<void> _openMoodPage() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => MoodPage(selectedMood: selectedMood),
      ),
    );

    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedMood', result);

    if (!mounted) return;

    setState(() => selectedMood = result);
  }

  Future<void> _openWardrobePage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WardrobePage(
          clothes: clothes,
          onClothesChanged: _saveClothes,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  void _openMirror() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MirrorPage(
          mood: selectedMood,
          weather: weather,
          clothes: clothes,
        ),
      ),
    );
  }

  void _openOutfitRecommendation() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OutfitPage(
          clothes: clothes,
          mood: selectedMood,
          weather: weather,
        ),
      ),
    );
  }

  void _openCalendar() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const CalendarPage(),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWeather,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 35),
            children: [
              // LOGO CENTRADO INDEPENDIENTEMENTE DEL BOTÓN DE AJUSTES
              SizedBox(
                height: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/mirrormood_logo.jpg',
                        height: 58,
                        width: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            'MIRRORMOOD',
                            style: TextStyle(
                              color: primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: IconButton(
                        onPressed: () => widget.onOpenSettings(context),
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Personalizar apariencia',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                '${_getGreeting()} 👋',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.65),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tu día, tu estilo. ✨',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),

              const SizedBox(height: 30),

              // ESPEJO
              Card(
                child: InkWell(
                  onTap: _openMirror,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.face_retouching_natural,
                            color: primary,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'MI ESPEJO',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Mírate, descubre tu estilo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openMirror,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Abrir mi espejo'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CLIMA Y ESTADO
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildCompactCard(
                      icon: weather?.icon ?? '🌤️',
                      label: 'CLIMA',
                      value: loadingWeather
                          ? '...'
                          : weather == null
                              ? 'Sin datos'
                              : '${weather!.temperature.toStringAsFixed(0)}°C',
                      subtitle: loadingWeather
                          ? 'Consultando'
                          : weather?.description ?? 'No disponible',
                      onTap: _loadWeather,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCompactCard(
                      icon: selectedMood == null
                          ? '😶'
                          : _getMoodEmoji(selectedMood!),
                      label: 'MI ESTADO',
                      value: selectedMood ?? 'Sin elegir',
                      subtitle: selectedMood == null
                          ? '¿Cómo te sientes?'
                          : 'Estado de hoy',
                      onTap: _openMoodPage,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: primary),
                  const SizedBox(width: 8),
                  const Text(
                    'TU ESTILO DE HOY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Card(
                child: InkWell(
                  onTap: clothes.isEmpty
                      ? _openWardrobePage
                      : _openOutfitRecommendation,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.all(19),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.checkroom_outlined,
                            color: primary,
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clothes.isEmpty
                                    ? 'Prepara tu armario'
                                    : 'Recomiéndame un outfit',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                clothes.isEmpty
                                    ? 'Agrega prendas para comenzar'
                                    : selectedMood == null
                                        ? 'Un look pensado para ti'
                                        : 'Según tu estado y el clima',
                                style: TextStyle(
                                  color: onSurface.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 17,
                          color: onSurface.withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'ACCESOS RÁPIDOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.checkroom_outlined,
                      title: 'Armario',
                      subtitle:
                          clothes.isEmpty ? 'Vacío' : '${clothes.length} prendas',
                      onTap: _openWardrobePage,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.mood_outlined,
                      title: 'Mi estado',
                      subtitle: selectedMood ?? 'Sin elegir',
                      onTap: _openMoodPage,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.calendar_month_outlined,
                      title: 'Calendario',
                      subtitle: 'Organiza tu día',
                      onTap: _openCalendar,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.palette_outlined,
                      title: 'Apariencia',
                      subtitle: 'Personaliza',
                      onTap: () => widget.onOpenSettings(context),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.format_quote, color: primary, size: 30),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FRASE DEL DÍA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              dailyPhrase,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),
              Center(
                child: Text(
                  'Tu estilo. Tu estado. Tu MirrorMood. ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCard({
    required String icon,
    required String label,
    required String value,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 25)),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: onSurface.withValues(alpha: 0.35),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: primary, size: 22),
              ),
              const SizedBox(height: 13),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMoodEmoji(String mood) {
    switch (mood) {
      case 'Feliz':
        return '😄';
      case 'Tranquilo':
        return '😌';
      case 'Motivado':
        return '🔥';
      case 'Cansado':
        return '😴';
      case 'Triste':
        return '😔';
      case 'Energético':
        return '⚡';
      default:
        return '😶';
    }
  }
}

// ============================================================
// MOOD PAGE
// ============================================================

class MoodPage extends StatefulWidget {
  final String? selectedMood;

  const MoodPage({super.key, this.selectedMood});

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage> {
  late String? selectedMood;

  final List<Map<String, String>> moods = [
    {'name': 'Feliz', 'emoji': '😄'},
    {'name': 'Tranquilo', 'emoji': '😌'},
    {'name': 'Motivado', 'emoji': '🔥'},
    {'name': 'Cansado', 'emoji': '😴'},
    {'name': 'Triste', 'emoji': '😔'},
    {'name': 'Energético', 'emoji': '⚡'},
  ];

  @override
  void initState() {
    super.initState();
    selectedMood = widget.selectedMood;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi estado de ánimo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '¿Cómo te sientes hoy?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu estado ayudará a MirrorMood a recomendarte un estilo.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 24),
          ...moods.map((mood) {
            final isSelected = selectedMood == mood['name'];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: isSelected
                    ? scheme.primary.withValues(alpha: 0.18)
                    : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => setState(() {
                    selectedMood = mood['name'];
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Text(
                          mood['emoji']!,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            mood['name']!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            height: 55,
            child: FilledButton(
              onPressed: selectedMood == null
                  ? null
                  : () => Navigator.pop(context, selectedMood),
              child: const Text('Guardar mi estado'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WARDROBE PAGE
// ============================================================

class WardrobePage extends StatefulWidget {
  final List<Map<String, String>> clothes;
  final Future<void> Function() onClothesChanged;

  const WardrobePage({
    super.key,
    required this.clothes,
    required this.onClothesChanged,
  });

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  final List<String> categories = [
    'Camiseta',
    'Pantalón',
    'Chaqueta',
    'Zapatos',
    'Accesorio',
  ];

  final List<String> colors = [
    'Negro',
    'Blanco',
    'Azul',
    'Rojo',
    'Verde',
    'Amarillo',
    'Gris',
    'Marrón',
    'Otro',
  ];

  final List<String> styles = [
    'Casual',
    'Deportivo',
    'Elegante',
    'Cómodo',
    'Urbano',
  ];

  Future<void> _addClothing() async {
    final nameController = TextEditingController();

    String category = categories.first;
    String color = colors.first;
    String style = styles.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar prenda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Ej: Camiseta negra',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: categories
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => category = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: color,
                  decoration: const InputDecoration(labelText: 'Color'),
                  items: colors
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => color = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: style,
                  decoration: const InputDecoration(labelText: 'Estilo'),
                  items: styles
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => style = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                widget.clothes.add({
                  'name': name,
                  'category': category,
                  'color': color,
                  'style': style,
                });

                await widget.onClothesChanged();

                if (mounted) setState(() {});
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();

    if (mounted) setState(() {});
  }

  Future<void> _deleteClothing(int index) async {
    widget.clothes.removeAt(index);
    await widget.onClothesChanged();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi armario')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClothing,
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: widget.clothes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.checkroom_outlined,
                      size: 70,
                      color: scheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Tu armario está vacío',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Agrega algunas prendas para que MirrorMood pueda crear outfits.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.clothes.length,
              itemBuilder: (context, index) {
                final item = widget.clothes[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          scheme.primary.withValues(alpha: 0.15),
                      child: Icon(
                        _getCategoryIcon(item['category']),
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      item['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${item['category']} • ${item['color']} • ${item['style']}',
                    ),
                    trailing: IconButton(
                      onPressed: () => _deleteClothing(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Pantalón':
        return Icons.straighten;
      case 'Chaqueta':
        return Icons.checkroom;
      case 'Zapatos':
        return Icons.directions_run;
      case 'Accesorio':
        return Icons.watch_outlined;
      default:
        return Icons.checkroom_outlined;
    }
  }
}

// ============================================================
// OUTFIT PAGE
// ============================================================

class OutfitPage extends StatelessWidget {
  final List<Map<String, String>> clothes;
  final String? mood;
  final WeatherData? weather;

  const OutfitPage({
    super.key,
    required this.clothes,
    required this.mood,
    required this.weather,
  });

  Map<String, String>? _findBest(
    String category, {
    List<String> preferredStyles = const [],
    List<String> preferredColors = const [],
  }) {
    final matching =
        clothes.where((item) => item['category'] == category).toList();

    if (matching.isEmpty) return null;

    for (final item in matching) {
      if (preferredStyles.contains(item['style'])) return item;
    }
    for (final item in matching) {
      if (preferredColors.contains(item['color'])) return item;
    }
    return matching.first;
  }

  Map<String, Map<String, String>?> _buildOutfit() {
    List<String> preferredStyles = [];
    List<String> preferredColors = [];

    switch (mood) {
      case 'Motivado':
      case 'Energético':
        preferredStyles = ['Deportivo', 'Urbano'];
        break;
      case 'Tranquilo':
      case 'Cansado':
        preferredStyles = ['Cómodo'];
        break;
      case 'Feliz':
        preferredStyles = ['Casual'];
        break;
      case 'Triste':
        preferredColors = ['Negro', 'Gris', 'Azul'];
        break;
    }

    final shirt = _findBest(
      'Camiseta',
      preferredStyles: preferredStyles,
      preferredColors: preferredColors,
    );
    final pants = _findBest(
      'Pantalón',
      preferredStyles: preferredStyles,
      preferredColors: preferredColors,
    );
    final shoes = _findBest(
      'Zapatos',
      preferredStyles: preferredStyles,
      preferredColors: preferredColors,
    );

    Map<String, String>? jacket;
    if (weather != null && (weather!.isRainy || weather!.isCold)) {
      jacket = _findBest(
        'Chaqueta',
        preferredStyles: preferredStyles,
        preferredColors: preferredColors,
      );
    }

    return {
      'Camiseta': shirt,
      'Pantalón': pants,
      'Zapatos': shoes,
      'Chaqueta': jacket,
    };
  }

  @override
  Widget build(BuildContext context) {
    final outfit = _buildOutfit();
    final hasAny = outfit.values.any((item) => item != null);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tu outfit')),
      body: !hasAny
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome, size: 65),
                    const SizedBox(height: 18),
                    const Text(
                      'Necesito más prendas',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Agrega algunas prendas a tu armario para crear un outfit.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 35,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          '✨ TU OUTFIT DE HOY',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mood == null
                              ? 'Un look pensado para ti.'
                              : 'Pensado para tu estado: $mood',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...outfit.entries
                    .where((entry) => entry.value != null)
                    .map(
                      (entry) => _buildClothingCard(
                        context,
                        entry.key,
                        entry.value!,
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _buildClothingCard(
    BuildContext context,
    String category,
    Map<String, String> item,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: scheme.primary.withValues(alpha: 0.14),
          child: Icon(Icons.checkroom, color: scheme.primary),
        ),
        title: Text(
          category,
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${item['name']} • ${item['color']} • ${item['style']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ============================================================
// MIRROR PAGE
// ============================================================

class MirrorPage extends StatefulWidget {
  final String? mood;
  final WeatherData? weather;
  final List<Map<String, String>> clothes;

  const MirrorPage({
    super.key,
    required this.mood,
    required this.weather,
    required this.clothes,
  });

  @override
  State<MirrorPage> createState() => _MirrorPageState();
}

class _MirrorPageState extends State<MirrorPage> {
  CameraController? controller;
  bool initializing = true;
  bool cameraError = false;
  int cameraIndex = 0;
  List<CameraDescription> cameras = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          cameraError = true;
          initializing = false;
        });
        return;
      }

      final frontIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      cameraIndex = frontIndex >= 0 ? frontIndex : 0;

      final newController = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );

      controller = newController;
      await newController.initialize();

      if (!mounted) return;
      setState(() => initializing = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        cameraError = true;
        initializing = false;
      });
    }
  }

  Future<void> _flipCamera() async {
    if (cameras.length < 2) return;

    try {
      final currentController = controller;
      controller = null;
      await currentController?.dispose();

      cameraIndex = (cameraIndex + 1) % cameras.length;

      final newController = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );

      controller = newController;
      await newController.initialize();

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => cameraError = true);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  String _phrase() {
    switch (widget.mood) {
      case 'Feliz':
        return 'Sonríe. Hoy es tu día. 😄';
      case 'Motivado':
        return 'Vamos con toda. 🔥';
      case 'Energético':
        return 'Tu energía se nota. ⚡';
      case 'Tranquilo':
        return 'Disfruta el momento. 😌';
      case 'Cansado':
        return 'Sin presión. Ve a tu ritmo. 😴';
      case 'Triste':
        return 'Mañana puede ser diferente. 💜';
      default:
        return 'Confía en tu estilo. ✨';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !initializing &&
        !cameraError &&
        controller != null &&
        controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            CameraPreview(controller!)
          else
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      cameraError
                          ? Icons.camera_alt_outlined
                          : Icons.hourglass_top,
                      color: Colors.white,
                      size: 65,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      cameraError
                          ? 'No se pudo abrir la cámara'
                          : 'Abriendo tu espejo...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (cameraError) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Comprueba los permisos de cámara o prueba en un teléfono Android.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 15),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            initializing = true;
                            cameraError = false;
                          });
                          _initializeCamera();
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (widget.mood != null) _mirrorBadge(widget.mood!),
                  if (widget.weather != null) ...[
                    const SizedBox(width: 8),
                    _mirrorBadge(
                      '${widget.weather!.temperature.toStringAsFixed(0)}°',
                    ),
                  ],
                ],
              ),
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 100,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    '✨ TU OUTFIT DE HOY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _phrase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            right: 18,
            bottom: 22,
            child: CircleAvatar(
              radius: 27,
              backgroundColor: Colors.black.withValues(alpha: 0.55),
              child: IconButton(
                onPressed: _flipCamera,
                icon: const Icon(
                  Icons.flip_camera_ios,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mirrorBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ============================================================
// CALENDARIO, EVENTOS Y RECORDATORIOS
// ============================================================

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime dateTime;
  final String priority;
  final int? reminderMinutes;
  final bool isTask;
  final bool isDone;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.priority,
    required this.reminderMinutes,
    required this.isTask,
    required this.isDone,
  });

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dateTime,
    String? priority,
    int? reminderMinutes,
    bool clearReminder = false,
    bool? isTask,
    bool? isDone,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      priority: priority ?? this.priority,
      reminderMinutes:
          clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
      isTask: isTask ?? this.isTask,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dateTime': dateTime.toIso8601String(),
        'priority': priority,
        'reminderMinutes': reminderMinutes,
        'isTask': isTask,
        'isDone': isDone,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Actividad',
      description: json['description']?.toString() ?? '',
      dateTime: DateTime.tryParse(json['dateTime']?.toString() ?? '') ??
          DateTime.now(),
      priority: json['priority']?.toString() ?? 'Normal',
      reminderMinutes: json['reminderMinutes'] is num
          ? (json['reminderMinutes'] as num).toInt()
          : null,
      isTask: json['isTask'] == true,
      isDone: json['isDone'] == true,
    );
  }
}

class CalendarNotificationService {
  CalendarNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> initialize() async {
    // El calendario también funciona en Chrome; las notificaciones locales
    // se preparan en los dispositivos compatibles, como Android.
    if (kIsWeb) return;

    try {
      tz_data.initializeTimeZones();
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(settings: settings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      _initialized = true;
    } catch (_) {
      // Si las notificaciones no se pueden iniciar, la agenda y el guardado
      // de eventos siguen funcionando normalmente.
    }
  }

  static int notificationId(String eventId) {
    // Hash estable: permite cancelar la notificación incluso tras reiniciar.
    var hash = 0x811c9dc5;
    for (final unit in eventId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<void> cancel(String eventId) async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancel(id: notificationId(eventId));
    } catch (_) {}
  }

  static Future<bool> schedule(CalendarEvent event) async {
    if (kIsWeb || !_initialized || event.reminderMinutes == null) {
      return false;
    }

    final reminderTime = event.dateTime.subtract(
      Duration(minutes: event.reminderMinutes!),
    );

    if (!reminderTime.isAfter(DateTime.now())) return false;

    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'mirrormood_calendar',
          'Recordatorios de MirrorMood',
          channelDescription: 'Avisos de tus eventos y tareas.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      );

      await _plugin.zonedSchedule(
        id: notificationId(event.id),
        title: event.isTask ? 'Tarea pendiente' : 'Próximo evento',
        body: event.title,
        scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: event.id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime focusedDate = DateTime.now();
  DateTime selectedDate = DateTime.now();
  List<CalendarEvent> events = [];
  bool loading = true;

  final DateFormat _dayFormat = DateFormat('EEEE d MMMM yyyy', 'es_ES');
  final DateFormat _timeFormat = DateFormat('HH:mm', 'es_ES');

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('selectedCalendarDate');
    final savedEvents = prefs.getString('calendarEvents');

    DateTime? parsedDate;
    if (savedDate != null) {
      parsedDate = DateTime.tryParse(savedDate);
    }

    final loadedEvents = <CalendarEvent>[];
    if (savedEvents != null) {
      try {
        final decoded = jsonDecode(savedEvents);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              loadedEvents.add(
                CalendarEvent.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } catch (_) {
        // Si los datos antiguos estuvieran dañados, no se bloquea el calendario.
      }
    }

    loadedEvents.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (!mounted) return;

    setState(() {
      if (parsedDate != null) {
        selectedDate = _dateOnly(parsedDate);
        focusedDate = _dateOnly(parsedDate);
      }
      events = loadedEvents;
      loading = false;
    });
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedCalendarDate', selectedDate.toIso8601String());
    await prefs.setString(
      'calendarEvents',
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    return events
        .where((event) => isSameDay(event.dateTime, day))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Future<void> _selectDay(DateTime selected, DateTime focused) async {
    setState(() {
      selectedDate = _dateOnly(selected);
      focusedDate = _dateOnly(focused);
    });
    await _saveAll();
  }

  Future<void> _openEventEditor({CalendarEvent? existing}) async {
    final result = await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => _CalendarEventDialog(
        initialDate: selectedDate,
        event: existing,
      ),
    );

    if (result == null || !mounted) return;

    final oldEvent = existing;
    if (oldEvent != null) {
      await CalendarNotificationService.cancel(oldEvent.id);
      events.removeWhere((event) => event.id == oldEvent.id);
    }

    events.add(result);
    events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    selectedDate = _dateOnly(result.dateTime);
    focusedDate = _dateOnly(result.dateTime);
    await _saveAll();

    if (result.reminderMinutes != null) {
      final scheduled = await CalendarNotificationService.schedule(result);
      if (!mounted) return;
      if (kIsWeb) {
        _showMessage(
          'El evento se guardó. Para recibir notificaciones, usa la versión Android.',
          icon: Icons.info_outline,
        );
      } else if (!scheduled) {
        _showMessage(
          'Evento guardado. El recordatorio no se pudo programar porque su hora ya pasó o las notificaciones no están disponibles.',
          icon: Icons.notifications_off_outlined,
        );
      } else {
        _showMessage('Evento guardado y recordatorio programado.',
            icon: Icons.notifications_active_outlined);
      }
    } else {
      _showMessage('Actividad guardada.');
    }

    if (mounted) setState(() {});
  }

  Future<void> _toggleTask(CalendarEvent event, bool done) async {
    final index = events.indexWhere((item) => item.id == event.id);
    if (index < 0) return;

    events[index] = events[index].copyWith(isDone: done);
    await _saveAll();
    if (mounted) setState(() {});
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar actividad'),
        content: Text('¿Quieres eliminar "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await CalendarNotificationService.cancel(event.id);
    events.removeWhere((item) => item.id == event.id);
    await _saveAll();
    if (mounted) {
      setState(() {});
      _showMessage('Actividad eliminada.');
    }
  }

  void _showMessage(String message, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Color _priorityColor(String priority, ColorScheme scheme) {
    switch (priority) {
      case 'Urgente':
        return const Color(0xFFFF5C72);
      case 'Importante':
        return const Color(0xFFFFB547);
      default:
        return scheme.primary;
    }
  }

  String _reminderLabel(int? minutes) {
    if (minutes == null) return 'Sin recordatorio';
    if (minutes == 0) return 'A la hora del evento';
    if (minutes == 10) return '10 minutos antes';
    if (minutes == 30) return '30 minutos antes';
    if (minutes == 60) return '1 hora antes';
    if (minutes == 1440) return '1 día antes';
    return '$minutes minutos antes';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayEvents = _eventsForDay(selectedDate);
    final completed = dayEvents.where((event) => event.isTask && event.isDone).length;
    final tasks = dayEvents.where((event) => event.isTask).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi agenda'),
        actions: [
          IconButton(
            tooltip: 'Ir a hoy',
            onPressed: () => _selectDay(DateTime.now(), DateTime.now()),
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEventEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva actividad'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    child: TableCalendar<CalendarEvent>(
                      locale: 'es_ES',
                      firstDay: DateTime(2020, 1, 1),
                      lastDay: DateTime(2035, 12, 31),
                      focusedDay: focusedDate,
                      selectedDayPredicate: (day) => isSameDay(selectedDate, day),
                      eventLoader: _eventsForDay,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Mes',
                      },
                      onDaySelected: _selectDay,
                      onPageChanged: (focused) {
                        setState(() => focusedDate = focused);
                      },
                      headerStyle: const HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                        leftChevronIcon: Icon(Icons.chevron_left),
                        rightChevronIcon: Icon(Icons.chevron_right),
                      ),
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        todayDecoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: BoxDecoration(
                          color: scheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                        markersMaxCount: 3,
                        weekendTextStyle: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AGENDA DEL DÍA',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _dayFormat.format(selectedDate),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tasks > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '$completed/$tasks tareas',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (dayEvents.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 48,
                            color: scheme.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Tu día está despejado',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Agrega un evento o una tarea para organizarte mejor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () => _openEventEditor(),
                            icon: const Icon(Icons.add),
                            label: const Text('Crear actividad'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...dayEvents.map((event) => _buildEventCard(event, scheme)),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recordatorios',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                kIsWeb
                                    ? 'Los eventos se guardan en este navegador. Las notificaciones locales se deben probar en Android.'
                                    : 'Puedes elegir un aviso al crear cada actividad. En Android, permite las notificaciones cuando el sistema lo solicite.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: scheme.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEventCard(CalendarEvent event, ColorScheme scheme) {
    final priorityColor = _priorityColor(event.priority, scheme);
    final done = event.isTask && event.isDone;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openEventEditor(existing: event),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.isTask)
                Checkbox(
                  value: event.isDone,
                  onChanged: (value) =>
                      _toggleTask(event, value ?? false),
                )
              else
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.event_outlined, color: priorityColor),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          color: done
                              ? scheme.onSurface.withValues(alpha: 0.5)
                              : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 14,
                              color: scheme.onSurface.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(
                            _timeFormat.format(event.dateTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: priorityColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              event.priority,
                              style: TextStyle(
                                fontSize: 10,
                                color: priorityColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (event.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                      if (event.reminderMinutes != null) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(Icons.notifications_none,
                                size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _reminderLabel(event.reminderMinutes),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'edit') {
                    _openEventEditor(existing: event);
                  } else if (value == 'delete') {
                    _deleteEvent(event);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarEventDialog extends StatefulWidget {
  final DateTime initialDate;
  final CalendarEvent? event;

  const _CalendarEventDialog({
    required this.initialDate,
    this.event,
  });

  @override
  State<_CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<_CalendarEventDialog> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late DateTime dateTime;
  late String priority;
  late bool isTask;
  late bool isDone;
  late int reminderChoice;

  final DateFormat _dateFormat = DateFormat('EEE d MMM', 'es_ES');

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    titleController = TextEditingController(text: event?.title ?? '');
    descriptionController =
        TextEditingController(text: event?.description ?? '');
    dateTime = event?.dateTime ??
        DateTime(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day,
          DateTime.now().hour + 1,
          0,
        );
    priority = event?.priority ?? 'Normal';
    isTask = event?.isTask ?? false;
    isDone = event?.isDone ?? false;
    reminderChoice = event?.reminderMinutes ?? -1;
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      locale: const Locale('es', 'ES'),
    );
    if (picked == null) return;
    setState(() {
      dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        dateTime.hour,
        dateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dateTime),
    );
    if (picked == null) return;
    setState(() {
      dateTime = DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    final title = titleController.text.trim();
    if (title.isEmpty) return;

    final oldEvent = widget.event;
    final newEvent = CalendarEvent(
      id: oldEvent?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      description: descriptionController.text.trim(),
      dateTime: dateTime,
      priority: priority,
      reminderMinutes: reminderChoice < 0 ? null : reminderChoice,
      isTask: isTask,
      isDone: isTask ? isDone : false,
    );
    Navigator.pop(context, newEvent);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEditing = widget.event != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar actividad' : 'Nueva actividad'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  hintText: 'Ej. Entrega de proyecto',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isTask,
                onChanged: (value) => setState(() => isTask = value),
                title: const Text('Es una tarea'),
                subtitle: const Text('Podrás marcarla como completada'),
                secondary: Icon(
                  Icons.check_circle_outline,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(
                  labelText: 'Prioridad',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                  DropdownMenuItem(
                      value: 'Importante', child: Text('Importante')),
                  DropdownMenuItem(value: 'Urgente', child: Text('Urgente')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => priority = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(_dateFormat.format(dateTime)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: reminderChoice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Recordatorio',
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: -1, child: Text('Sin recordatorio')),
                  DropdownMenuItem(value: 0, child: Text('A la hora del evento')),
                  DropdownMenuItem(value: 10, child: Text('10 minutos antes')),
                  DropdownMenuItem(value: 30, child: Text('30 minutos antes')),
                  DropdownMenuItem(value: 60, child: Text('1 hora antes')),
                  DropdownMenuItem(value: 1440, child: Text('1 día antes')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => reminderChoice = value);
                },
              ),
              if (isEditing && isTask) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDone,
                  onChanged: (value) =>
                      setState(() => isDone = value ?? false),
                  title: const Text('Tarea completada'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Los cambios se guardarán automáticamente.',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================
// SETTINGS / PERSONALIZACIÓN
// ============================================================

class SettingsPage extends StatefulWidget {
  final Color backgroundColor;
  final Color accentColor;
  final Color cardColor;

  final Future<void> Function({
    Color? background,
    Color? accent,
    Color? card,
  }) onAppearanceChanged;

  const SettingsPage({
    super.key,
    required this.backgroundColor,
    required this.accentColor,
    required this.cardColor,
    required this.onAppearanceChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Color backgroundColor;
  late Color accentColor;
  late Color cardColor;

  @override
  void initState() {
    super.initState();
    backgroundColor = widget.backgroundColor;
    accentColor = widget.accentColor;
    cardColor = widget.cardColor;
  }

  Future<void> _changeColors({
    Color? background,
    Color? accent,
    Color? card,
  }) async {
    setState(() {
      if (background != null) backgroundColor = background;
      if (accent != null) accentColor = accent;
      if (card != null) cardColor = card;
    });

    await widget.onAppearanceChanged(
      background: background,
      accent: accent,
      card: card,
    );
  }

  void _applyTheme(Color background, Color accent, Color card) {
    _changeColors(
      background: background,
      accent: accent,
      card: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar apariencia')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Haz MirrorMood tuyo.',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Cambia los colores generales de la aplicación.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 24),
          const Text(
            'TEMAS RÁPIDOS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _themeButton(
            'Nocturno',
            Icons.dark_mode_outlined,
            const Color(0xFF0D0D12),
            const Color(0xFF8B5CF6),
            const Color(0xFF17171F),
          ),
          _themeButton(
            'Océano',
            Icons.water_outlined,
            const Color(0xFF07131F),
            const Color(0xFF38BDF8),
            const Color(0xFF102333),
          ),
          _themeButton(
            'Naturaleza',
            Icons.eco_outlined,
            const Color(0xFF0B1510),
            const Color(0xFF4ADE80),
            const Color(0xFF14221A),
          ),
          _themeButton(
            'Energía',
            Icons.bolt_outlined,
            const Color(0xFF171005),
            const Color(0xFFF59E0B),
            const Color(0xFF241A0A),
          ),
          _themeButton(
            'Rosa',
            Icons.favorite_border,
            const Color(0xFF180B13),
            const Color(0xFFF472B6),
            const Color(0xFF27121F),
          ),
          const SizedBox(height: 28),
          const Text(
            'PERSONALIZACIÓN AVANZADA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 15),
          _colorSlider(
            title: 'Fondo de la aplicación',
            color: backgroundColor,
            onChanged: (color) => _changeColors(background: color),
          ),
          const SizedBox(height: 20),
          _colorSlider(
            title: 'Color de acento',
            color: accentColor,
            onChanged: (color) => _changeColors(accent: color),
          ),
          const SizedBox(height: 20),
          _colorSlider(
            title: 'Color de las tarjetas',
            color: cardColor,
            onChanged: (color) => _changeColors(card: color),
          ),
          const SizedBox(height: 28),
          const Text(
            'VISTA PREVIA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: cardColor,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.auto_awesome, color: accentColor),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Así se verá tu MirrorMood.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Los cambios se guardan automáticamente.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 15),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Botón de ejemplo'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _themeButton(
    String name,
    IconData icon,
    Color background,
    Color accent,
    Color card,
  ) {
    final isSelected =
        colorToInt(backgroundColor) == colorToInt(background) &&
        colorToInt(accentColor) == colorToInt(accent) &&
        colorToInt(cardColor) == colorToInt(card);

    return Card(
      color: isSelected ? accentColor.withValues(alpha: 0.15) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _applyTheme(background, accent, card),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorSlider({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return _ColorSliderCard(
      title: title,
      color: color,
      onChanged: onChanged,
    );
  }
}

// Widget separado para que los controles RGB mantengan su estado correctamente.
class _ColorSliderCard extends StatefulWidget {
  final String title;
  final Color color;
  final ValueChanged<Color> onChanged;

  const _ColorSliderCard({
    required this.title,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_ColorSliderCard> createState() => _ColorSliderCardState();
}

class _ColorSliderCardState extends State<_ColorSliderCard> {
  late double red;
  late double green;
  late double blue;

  @override
  void initState() {
    super.initState();
    _setChannels(widget.color);
  }

  @override
  void didUpdateWidget(covariant _ColorSliderCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (colorToInt(oldWidget.color) != colorToInt(widget.color)) {
      _setChannels(widget.color);
    }
  }

  void _setChannels(Color color) {
    red = colorRed(color).toDouble();
    green = colorGreen(color).toDouble();
    blue = colorBlue(color).toDouble();
  }

  Color get currentColor => Color.fromARGB(
        255,
        red.round(),
        green.round(),
        blue.round(),
      );

  void _updateColor() {
    widget.onChanged(currentColor);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text('Rojo: ${red.round()}'),
            Slider(
              value: red,
              min: 0,
              max: 255,
              onChanged: (value) {
                setState(() => red = value);
                _updateColor();
              },
            ),
            Text('Verde: ${green.round()}'),
            Slider(
              value: green,
              min: 0,
              max: 255,
              onChanged: (value) {
                setState(() => green = value);
                _updateColor();
              },
            ),
            Text('Azul: ${blue.round()}'),
            Slider(
              value: blue,
              min: 0,
              max: 255,
              onChanged: (value) {
                setState(() => blue = value);
                _updateColor();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// WEATHER
// ============================================================

class WeatherData {
  final double temperature;
  final int weatherCode;
  final String description;
  final bool isRainy;
  final bool isCold;
  final bool isHot;

  const WeatherData({
    required this.temperature,
    required this.weatherCode,
    required this.description,
    required this.isRainy,
    required this.isCold,
    required this.isHot,
  });

  String get icon {
    if (isRainy) return '🌧️';
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 3) return '⛅';
    if (weatherCode >= 71 && weatherCode <= 77) return '❄️';
    return '🌤️';
  }
}

class WeatherService {
  static Future<WeatherData?> getWeather() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5));

      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 8));
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 10));

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}'
        '&longitude=${position.longitude}'
        '&current=temperature_2m,weather_code'
        '&timezone=auto',
      );

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final current = decoded['current'];
      if (current is! Map<String, dynamic>) return null;

      final temperatureValue = current['temperature_2m'];
      final codeValue = current['weather_code'];

      if (temperatureValue is! num || codeValue is! num) return null;

      final temperature = temperatureValue.toDouble();
      final code = codeValue.toInt();

      return WeatherData(
        temperature: temperature,
        weatherCode: code,
        description: _weatherDescription(code),
        isRainy: code >= 51 && code <= 82,
        isCold: temperature <= 18,
        isHot: temperature >= 27,
      );
    } catch (_) {
      return null;
    }
  }

  static String _weatherDescription(int code) {
    if (code == 0) return 'Despejado';
    if (code <= 3) return 'Parcialmente nublado';
    if (code >= 51 && code <= 67) return 'Lluvia';
    if (code >= 71 && code <= 77) return 'Nieve';
    if (code >= 80 && code <= 82) return 'Lluvias';
    if (code >= 95) return 'Tormenta';
    return 'Nublado';
  }
}