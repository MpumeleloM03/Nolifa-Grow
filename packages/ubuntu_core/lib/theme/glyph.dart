import 'package:flutter/material.dart';

/// Draws what used to be an emoji as a Material icon, so the app looks the same
/// on every phone and reads as a finished product.
///
/// Data across the apps (products, crops, animals, hazards) still carries an
/// emoji as a short, stable key. [Glyph] turns that key into an icon and a
/// colour; by default it sits on a soft rounded tile of that colour.
class Glyph extends StatelessWidget {
  final String emoji;

  /// Roughly the font size the emoji used to be drawn at.
  final double size;

  /// Draw the icon on a tinted tile (true) or bare (false).
  final bool tile;

  /// Overrides the colour from the table.
  final Color? color;

  const Glyph(this.emoji, {super.key, this.size = 24, this.tile = true, this.color});

  static const _green = Color(0xFF2E9E6B);
  static const _leaf = Color(0xFF3FA34D);
  static const _blue = Color(0xFF2F7BC4);
  static const _red = Color(0xFFD64545);
  static const _orange = Color(0xFFE07B28);
  static const _amber = Color(0xFFD99A1E);
  static const _gold = Color(0xFFC9A227);
  static const _brown = Color(0xFFA0682E);
  static const _purple = Color(0xFF8A5CC2);
  static const _grey = Color(0xFF6B7C74);

  static const Map<String, (IconData, Color)> _table = {
    // Water and weather
    '💧': (Icons.water_drop, _blue),
    '🚰': (Icons.water, _blue),
    '🌊': (Icons.waves, _blue),
    '🚿': (Icons.shower, _blue),
    '🪣': (Icons.format_color_fill, _blue),
    '🌧': (Icons.umbrella, _blue),
    '🌦': (Icons.wb_cloudy, _blue),
    '⛅': (Icons.wb_cloudy, _grey),
    '🌤': (Icons.wb_sunny, _amber),
    '☀': (Icons.wb_sunny, _amber),
    '🥶': (Icons.ac_unit, _blue),
    '❄': (Icons.ac_unit, _blue),
    '💨': (Icons.air, _grey),
    '🔥': (Icons.local_fire_department, _orange),
    '🏜': (Icons.landscape, _amber),
    '🏞': (Icons.landscape, _green),
    '⚡': (Icons.bolt, _amber),
    '🔋': (Icons.battery_charging_full, _green),
    '🕯': (Icons.light_mode, _amber),
    '🔦': (Icons.flashlight_on, _amber),
    '💡': (Icons.lightbulb, _amber),
    // Animals
    '🐄': (Icons.pets, _brown),
    '🐐': (Icons.pets, _brown),
    '🐑': (Icons.pets, _grey),
    '🐴': (Icons.pets, _brown),
    '🐔': (Icons.egg_alt, _orange),
    '🐛': (Icons.bug_report, _brown),
    '🩺': (Icons.medical_services, _red),
    // Crops and food
    '🌿': (Icons.eco, _leaf),
    '🌱': (Icons.spa, _leaf),
    '🌾': (Icons.grass, _gold),
    '🌽': (Icons.grain, _gold),
    '🥬': (Icons.eco, _leaf),
    '🥦': (Icons.eco, _green),
    '🥗': (Icons.eco, _leaf),
    '🫑': (Icons.spa, _green),
    '🍅': (Icons.spa, _red),
    '🍎': (Icons.spa, _red),
    '🍉': (Icons.spa, _red),
    '🍊': (Icons.spa, _orange),
    '🥕': (Icons.spa, _orange),
    '🎃': (Icons.spa, _orange),
    '🥭': (Icons.spa, _amber),
    '🍌': (Icons.spa, _gold),
    '🍋': (Icons.spa, _gold),
    '🥑': (Icons.spa, _green),
    '🥔': (Icons.spa, _brown),
    '🍠': (Icons.spa, _purple),
    '🧅': (Icons.spa, _purple),
    '🫘': (Icons.grain, _brown),
    '🥚': (Icons.egg, _amber),
    '🥛': (Icons.local_drink, _blue),
    '🍯': (Icons.hive, _amber),
    '🍗': (Icons.set_meal, _orange),
    '🍂': (Icons.eco, _brown),
    '🥀': (Icons.local_florist, _red),
    '🧺': (Icons.shopping_basket, _brown),
    // Farm and work
    '🚜': (Icons.agriculture, _green),
    '⛏': (Icons.hardware, _grey),
    '🧰': (Icons.handyman, _grey),
    '🔬': (Icons.biotech, _green),
    '🧪': (Icons.science, _purple),
    '📐': (Icons.square_foot, _grey),
    '🧭': (Icons.explore, _blue),
    '🏭': (Icons.factory, _grey),
    '💼': (Icons.work, _brown),
    '🛢': (Icons.oil_barrel, _grey),
    '♻': (Icons.recycling, _green),
    '🤖': (Icons.smart_toy, _blue),
    '✨': (Icons.auto_awesome, _amber),
    '🔮': (Icons.auto_graph, _purple),
    '📈': (Icons.trending_up, _green),
    // Shopping, money and delivery
    '🛒': (Icons.shopping_cart, _green),
    '🏷': (Icons.sell, _green),
    '📦': (Icons.inventory_2, _brown),
    '📥': (Icons.move_to_inbox, _green),
    '📤': (Icons.outbox, _blue),
    '📭': (Icons.inbox, _grey),
    '🛵': (Icons.delivery_dining, _orange),
    '🚛': (Icons.local_shipping, _blue),
    '💳': (Icons.credit_card, _blue),
    '💰': (Icons.payments, _green),
    '👛': (Icons.account_balance_wallet, _green),
    '🧾': (Icons.receipt_long, _grey),
    '🤝': (Icons.handshake, _green),
    '⚖': (Icons.balance, _grey),
    // Roads and places
    '🚧': (Icons.construction, _amber),
    '🚦': (Icons.traffic, _amber),
    '🛣': (Icons.add_road, _grey),
    '🕳': (Icons.trip_origin, _brown),
    '📍': (Icons.place, _red),
    '🗺': (Icons.map, _green),
    '🌍': (Icons.public, _blue),
    '🏠': (Icons.home, _green),
    '🏘': (Icons.holiday_village, _green),
    // Safety and status
    '🚨': (Icons.notifications_active, _red),
    '🔔': (Icons.notifications, _amber),
    '🚩': (Icons.flag, _red),
    '⛔': (Icons.block, _red),
    '🚫': (Icons.block, _red),
    '💥': (Icons.flash_on, _red),
    '👮': (Icons.local_police, _blue),
    '🛡': (Icons.shield, _green),
    '🔒': (Icons.lock, _grey),
    '🔐': (Icons.lock, _grey),
    '🔑': (Icons.key, _gold),
    '🪪': (Icons.badge, _blue),
    '✅': (Icons.check_circle, _green),
    '🟢': (Icons.circle, _green),
    '🟡': (Icons.circle, _amber),
    '⚫': (Icons.circle, _grey),
    '💚': (Icons.favorite, _green),
    '🎉': (Icons.celebration, _amber),
    // People and comms
    '👥': (Icons.groups, _green),
    '🧑': (Icons.person, _green),
    '🗣': (Icons.record_voice_over, _green),
    '📡': (Icons.sensors, _blue),
    '📶': (Icons.signal_cellular_alt, _green),
    '📸': (Icons.photo_camera, _grey),
    '🔍': (Icons.search, _grey),
    '🔎': (Icons.search, _grey),
    '⚙': (Icons.settings, _grey),
    '⏱': (Icons.timer, _grey),
    '⏰': (Icons.alarm, _amber),
    '😴': (Icons.bedtime, _purple),
    '🔁': (Icons.repeat, _green),
    '➕': (Icons.add, _green),
  };

  /// The icon and colour for an emoji key, or a leaf if it is unknown.
  static (IconData, Color) lookup(String emoji) {
    final key = emoji.replaceAll('️', '').trim();
    return _table[key] ?? (key.isEmpty ? (Icons.circle, _grey) : (Icons.eco, _leaf));
  }

  @override
  Widget build(BuildContext context) {
    if (emoji.trim().isEmpty) return SizedBox(width: size, height: size);
    final (icon, c) = lookup(emoji);
    final col = color ?? c;
    if (!tile) return Icon(icon, size: size * 0.95, color: col);
    final box = size * 1.3;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(box * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.72, color: col),
    );
  }
}
