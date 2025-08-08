// location.dart
class LocationData {
  final String id;
  final String name;
  final String address;
  final String description;
  final String image;
  final double latitude;
  final double longitude;
  final String workTitle;

  LocationData({
    required this.id,
    required this.name,
    required this.address,
    required this.description,
    required this.image,
    required this.latitude,
    required this.longitude,
    required this.workTitle,
  });

  factory LocationData.fromFirestore(String id, Map<String, dynamic> data) {
    double _toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    return LocationData(
      id: id,
      name: (data['name'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      image: (data['image'] ?? '').toString(),
      latitude: _toDouble(data['latitude']),
      longitude: _toDouble(data['longitude']),
      workTitle: (data['workTitle'] ?? '').toString(),
    );
  }
}
