/// Where the demo's places are. Real addresses are looked up by the driver app;
/// these cover the seeded orders and farms, and are the fallback when a lookup
/// finds nothing. Latitude then longitude.
const placeCoords = <String, (double, double)>{
  'umlazi v section': (-29.9760, 30.8890),
  'umlazi d section': (-29.9540, 30.8870),
  'umlazi': (-29.9697, 30.8860),
  'kwa-mashu': (-29.7440, 30.9830),
  'kwamashu': (-29.7440, 30.9830),
  'chatsworth': (-29.9240, 30.8800),
  'pinetown': (-29.8140, 30.8590),
  'hillcrest': (-29.7830, 30.7620),
  'inanda': (-29.6960, 30.9420),
  'verulam': (-29.6480, 31.0450),
  'pietermaritzburg': (-29.6010, 30.3794),
  'midlands': (-29.5500, 30.2500),
  'durban': (-29.8587, 31.0218),
  'ethekwini': (-29.8587, 31.0218),
  // Demo farms.
  'mkhize family farm': (-29.6200, 30.4000),
  'sithole growers': (-29.6600, 31.0300),
  'dlamini mill': (-29.8300, 30.8700),
  'khumalo poultry': (-29.7100, 30.9600),
  'naidoo orchards': (-29.7900, 30.7500),
  'zulu co-op': (-29.9400, 30.8900),
  'nolifa depot': (-29.8650, 31.0100),
  'your farm': (-29.8140, 30.8590),
  // KwaZulu-Natal towns, so a farm or buyer in them can be placed.
  'howick': (-29.4750, 30.2300),
  'estcourt': (-29.0000, 29.8800),
  'ladysmith': (-28.5600, 29.7800),
  'newcastle': (-27.7570, 29.9320),
  'port shepstone': (-30.7410, 30.4550),
  'empangeni': (-28.7500, 31.9000),
  'richards bay': (-28.7830, 32.0380),
  'kwadukuza': (-29.3330, 31.2900),
  'stanger': (-29.3330, 31.2900),
  'eshowe': (-28.8960, 31.4700),
  'ulundi': (-28.3350, 31.4160),
  'amanzimtoti': (-30.0500, 30.8830),
  'umhlanga': (-29.7260, 31.0840),
  'westville': (-29.8330, 30.9300),
  'tongaat': (-29.5750, 31.1200),
  'ballito': (-29.5390, 31.2140),
  'scottburgh': (-30.2860, 30.7530),
  'underberg': (-29.7870, 29.5000),
  'margate': (-30.8640, 30.3700),
  'mooi river': (-29.2100, 29.9930),
  'greytown': (-29.0620, 30.5920),
  'kokstad': (-30.5500, 29.4200),
  'harding': (-30.5800, 29.8800),
  // Planned Nolifa hubs.
  'durban hub': (-29.8650, 31.0100),
  'pietermaritzburg hub': (-29.6010, 30.3794),
  'richards bay hub': (-28.7830, 32.0380),
};

const durbanCentre = (-29.8587, 31.0218);

/// The best known coordinates for a place or address, or null.
/// Matches the longest known name found inside the text.
(double, double)? lookupPlace(String text) {
  final t = text.toLowerCase();
  String? best;
  for (final k in placeCoords.keys) {
    if (t.contains(k) && (best == null || k.length > best.length)) best = k;
  }
  return best == null ? null : placeCoords[best];
}
