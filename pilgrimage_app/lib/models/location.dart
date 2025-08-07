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
    return LocationData(
      id: id,
      name: data['name'],
      address: data['address'],
      description: data['description'],
      image: data['image'],
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      workTitle: data['workTitle'],
    );
  }
}
