import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which side of Nolifa a person who farms and drives is looking at: 'farmer',
/// 'driver', or null for the one their account was made with.
final viewAsProvider = StateProvider<String?>((ref) => null);
