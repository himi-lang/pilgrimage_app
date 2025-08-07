// lib/map_screen.dart
import 'dart:isolate';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ← 追加
import 'firebase_service.dart';
import 'models/location.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final LatLng _center = const LatLng(35.6586, 139.7454);
  final Set<Marker> _markers = {};
  final FirebaseService _firebaseService = FirebaseService();
  late ReceivePort receivePort;

  @override
  void initState() {
    super.initState();
    _loadMarkers();

    final bool isTesting = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTesting) {
      receivePort = ReceivePort();
      Isolate.spawn(_heavyTask, receivePort.sendPort);
      receivePort.listen((data) => debugPrint('計算結果: $data'));
    }
  }

  /// Firestore から読み込んでマーカー追加
  Future<void> _loadMarkers() async {
    try {
      final locations = await _firebaseService.fetchLocations();
      debugPrint('📍 取得したスポット件数: ${locations.length}');
      setState(() {
        _markers.addAll(
          locations.map((location) {
            debugPrint('✔️ マーカー追加: ${location.name}');
            return Marker(
              markerId: MarkerId(location.id),
              position: LatLng(location.latitude, location.longitude),
              infoWindow: InfoWindow(
                title: location.name,
                snippet: location.workTitle,
              ),
            );
          }),
        );
      });
      // 最初の場所にカメラ移動
      if (locations.isNotEmpty) {
        final first = locations.first;
        mapController.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(first.latitude, first.longitude),
            14,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ マーカー取得エラー: $e');
    }
  }

  /// 重い処理サンプル
  static void _heavyTask(SendPort sendPort) {
    int result = 0;
    for (int i = 0; i < 1000000; i++) result += i;
    sendPort.send(result);
  }

  /// マップ生成時
  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  /// ← ここから追加：ログアウト処理
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    // これで main.dart 側の StreamBuilder が LoginScreen に戻します
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聖地巡礼マップ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
            onPressed: _signOut,
          ),
        ],
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
        markers: _markers,
      ),
    );
  }

  @override
  void dispose() {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      receivePort.close();
    }
    super.dispose();
  }
}
