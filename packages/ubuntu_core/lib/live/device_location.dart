import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:geolocator/geolocator.dart';

/// Why the phone could not say where it is, so a screen can say what to do.
enum LocationProblem { servicesOff, denied, deniedForever, unavailable }

/// The last reason a position could not be read, or null when the last read
/// worked. Screens that need a position show a short fix-it banner from it.
final locationProblem = ValueNotifier<LocationProblem?>(null);

/// Where the phone is right now, asking for permission once. Returns null when
/// location is off or refused (and sets [locationProblem]), so callers say so
/// instead of guessing.
Future<(double, double)?> deviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      locationProblem.value = LocationProblem.servicesOff;
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      locationProblem.value = LocationProblem.deniedForever;
      return null;
    }
    if (perm == LocationPermission.denied) {
      locationProblem.value = LocationProblem.denied;
      return null;
    }
    // A reading from the last few minutes is as good as a new one for "near you".
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 10) {
      locationProblem.value = null;
      return (last.latitude, last.longitude);
    }
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium))
          .timeout(const Duration(seconds: 10));
      locationProblem.value = null;
      return (p.latitude, p.longitude);
    } catch (_) {
      // A slow fix is not a refusal: fall back to whatever the phone last knew.
      if (last != null) {
        locationProblem.value = null;
        return (last.latitude, last.longitude);
      }
      rethrow;
    }
  } catch (e) {
    debugPrint('location: unavailable: $e');
    locationProblem.value ??= LocationProblem.unavailable;
    return null;
  }
}

/// Opens the phone's settings where the person can turn location on or allow
/// the app. Returns false when nothing could be opened.
Future<bool> openLocationFix() async {
  try {
    return locationProblem.value == LocationProblem.servicesOff
        ? await Geolocator.openLocationSettings()
        : await Geolocator.openAppSettings();
  } catch (_) {
    return false;
  }
}

/// A moving feed of the phone's position for tracking a trip.
Stream<Position> positionFeed({int distanceMetres = 15}) => Geolocator.getPositionStream(
    locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceMetres));
