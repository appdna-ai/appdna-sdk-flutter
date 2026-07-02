/// SPEC-070-C §3.13 — resolved location for an onboarding location field.
/// Mirrors the native `LocationData` (iOS `LocationData` / Android
/// `ai.appdna.sdk.onboarding.LocationData`).
class LocationData {
  final String formattedAddress;
  final String city;
  final String state;
  final String stateCode;
  final String country;
  final String countryCode;
  final double latitude;
  final double longitude;
  final String timezone;
  final int timezoneOffset;
  final String? postalCode;
  final String rawQuery;

  const LocationData({
    required this.formattedAddress,
    required this.city,
    required this.state,
    required this.stateCode,
    required this.country,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.timezoneOffset,
    this.postalCode,
    required this.rawQuery,
  });

  factory LocationData.fromMap(Map<dynamic, dynamic> map) {
    return LocationData(
      formattedAddress: map['formatted_address'] as String? ?? '',
      city: map['city'] as String? ?? '',
      state: map['state'] as String? ?? '',
      stateCode: map['state_code'] as String? ?? '',
      country: map['country'] as String? ?? '',
      countryCode: map['country_code'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timezone: map['timezone'] as String? ?? 'UTC',
      timezoneOffset: (map['timezone_offset'] as num?)?.toInt() ?? 0,
      postalCode: map['postal_code'] as String?,
      rawQuery: map['raw_query'] as String? ?? '',
    );
  }
}
