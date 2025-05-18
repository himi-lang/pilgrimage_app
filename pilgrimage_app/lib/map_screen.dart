import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;

  // 初期位置（例：東京タワー）
  final LatLng _center = LatLng(35.6586, 139.7454);

  // 結果を受け取るためのReceivePort
  late ReceivePort receivePort;

  @override
  void initState() {
    super.initState();
    // Isolateを使ってバックグラウンドで処理を開始
    receivePort = ReceivePort();
    Isolate.spawn(_heavyTask, receivePort.sendPort);

    // 結果を受け取る
    receivePort.listen((data) {
      print('計算結果: $data');
    });
  }

  // 重い処理を行う関数
  void _heavyTask(SendPort sendPort) {
    int result = 0;
    for (int i = 0; i < 1000000; i++) {
      result += i; // 重い計算
    }
    sendPort.send(result); // 結果をメインスレッドに送信
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('聖地巡礼マップ')),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
      ),
    );
  }

  @override
  void dispose() {
    receivePort.close(); // リソースを解放
    super.dispose();
  }
}
