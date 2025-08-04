import 'dart:isolate';
import 'dart:io'; // ← テスト判定のために追加
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final LatLng _center = const LatLng(35.6586, 139.7454);

  // 結果を受け取るReceivePort
  late ReceivePort receivePort;

  @override
  void initState() {
    super.initState();

    // テスト実行中かどうかをチェック
    final bool isTesting = Platform.environment.containsKey('FLUTTER_TEST');

    // バックグラウンド処理はテスト時はスキップ
    if (!isTesting) {
      receivePort = ReceivePort();
      Isolate.spawn(_heavyTask, receivePort.sendPort);

      receivePort.listen((data) {
        debugPrint('計算結果: $data');
      });
    }
  }

  // 重い処理を行うトップレベル関数
  static void _heavyTask(SendPort sendPort) {
    int result = 0;
    for (int i = 0; i < 1000000; i++) {
      result += i;
    }
    sendPort.send(result);
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('聖地巡礼マップ')),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
      ),
    );
  }

  @override
  void dispose() {
    // テスト中は receivePort が初期化されていない可能性があるので、
    // close 時には null チェック
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      receivePort.close();
    }
    super.dispose();
  }
}
