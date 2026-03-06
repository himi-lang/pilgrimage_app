// location.dart
class LocationData {
  //classで設計書を定義
  final String id;
  final String name;
  final String address;
  final String description;
  final String image;
  final double latitude;
  final double longitude;
  final String workTitle;

  LocationData({
    //LocationDataを使ってデータ挿入型を作る
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
    double toDouble(dynamic v) {
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
      latitude: toDouble(data['latitude']),
      longitude: toDouble(data['longitude']),
      workTitle: (data['workTitle'] ?? '').toString(),
    );
  }
}
