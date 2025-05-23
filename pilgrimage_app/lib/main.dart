import 'package:flutter/material.dart';
import 'map_screen.dart'; // さっき作ったファイルを読み込む

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '聖地巡礼アプリ',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MapScreen(), // ← map_screen.dart の画面を最初に表示
    );
  }
}
