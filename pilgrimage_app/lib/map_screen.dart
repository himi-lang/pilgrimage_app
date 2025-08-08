import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_service.dart';
import './models/location.dart'; // LocationData: id, name, address, description, image, latitude, longitude, workTitle

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // --- 検索 ---
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showCandidates = false; // 候補一覧の表示/非表示

  // --- 地図 ---
  final Completer<GoogleMapController> _mapCtrl =
      Completer<GoogleMapController>();
  bool _mapReady = false;
  bool _initialFitDone = false;
  LocationData? _selected;

  // ★ ② Enter確定まで再購読を走らせないため、Streamは1回だけ生成して保持
  late final Stream<List<LocationData>> _locationsStream;

  @override
  void initState() {
    super.initState();
    _locationsStream = FirebaseService().locationsStreamAllWorks();
  }

  // 初期カメラ位置：日本（海外スタート対策）
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(35.681236, 139.767125),
    zoom: 5.5,
    tilt: 0,
    bearing: 0,
  );

  // 日本の概形境界（※パン制限は解除済み）
  static final LatLngBounds _japanBounds = LatLngBounds(
    southwest: const LatLng(24.396308, 122.93457),
    northeast: const LatLng(45.551483, 153.986672),
  );

  // ピンへ飛ぶときのズーム
  static const double _hitZoom = 16.0;

  // 全スポット
  List<LocationData> _all = [];

  // --- 文字正規化 + 検索 ---
  String _normalize(String s) {
    final runes = s
        .trim()
        .toLowerCase()
        .runes
        .map((r) {
          if (r >= 0xFF01 && r <= 0xFF5E) return r - 0xFEE0; // 全角→半角
          if (r >= 0x30A1 && r <= 0x30F6) return r - 0x60; // カタカナ→ひらがな
          return r;
        })
        .where((r) {
          const drops = [0x0020, 0x3000, 0x3001, 0x3002]; // 空白・句読点除去
          return !drops.contains(r);
        });
    return String.fromCharCodes(runes);
  }

  bool _match(LocationData d, String q) {
    if (q.isEmpty) return true;
    final nq = _normalize(q);
    bool contains(String x) => _normalize(x).contains(nq);
    return contains(d.name) ||
        contains(d.address) ||
        contains(d.description) ||
        contains(d.workTitle);
  }

  List<LocationData> _filter(List<LocationData> list, String q) {
    final qs = q.trim();
    if (qs.isEmpty) return list;
    return list.where((d) => _match(d, qs)).toList();
  }

  // --- 地図操作ユーティリティ ---
  Future<GoogleMapController> _controller() async {
    final c = await _mapCtrl.future;
    return c;
  }

  Future<void> _goToLatLng(LatLng ll, {double zoom = _hitZoom}) async {
    final c = await _controller();
    try {
      await c.animateCamera(CameraUpdate.newLatLngZoom(ll, zoom));
    } catch (_) {
      await c.moveCamera(CameraUpdate.newLatLngZoom(ll, zoom));
    }
  }

  Future<void> _fitToAllIfNeeded() async {
    if (_initialFitDone || !_mapReady || _all.isEmpty) return;
    final c = await _controller();
    _initialFitDone = true;

    if (_all.length == 1) {
      final d = _all.first;
      try {
        await c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(d.latitude, d.longitude), zoom: 14),
          ),
        );
      } catch (_) {
        await c.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(d.latitude, d.longitude), zoom: 14),
          ),
        );
      }
      return;
    }

    double minLat = 90, minLng = 180, maxLat = -90, maxLng = -180;
    for (final d in _all) {
      if (d.latitude < minLat) minLat = d.latitude;
      if (d.latitude > maxLat) maxLat = d.latitude;
      if (d.longitude < minLng) minLng = d.longitude;
      if (d.longitude > maxLng) maxLng = d.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    const padding = 60.0;
    try {
      await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    } on PlatformException {
      await c.moveCamera(CameraUpdate.newCameraPosition(_initialCamera));
    }
  }

  // --- 候補パネル ---
  Widget _buildCandidatePanel(List<LocationData> items) {
    if (!_showCandidates || _searchCtrl.text.trim().isEmpty || items.isEmpty) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 320),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = items[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place),
                  title: Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (d.workTitle.isNotEmpty) d.workTitle,
                      if (d.address.isNotEmpty) d.address,
                    ].join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _onCandidateTap(d),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onCandidateTap(LocationData d) async {
    setState(() {
      _selected = d;
      _showCandidates = false;
    });
    FocusScope.of(context).unfocus();

    await Future.delayed(const Duration(milliseconds: 40));
    await _goToLatLng(LatLng(d.latitude, d.longitude), zoom: _hitZoom);

    try {
      final c = await _controller();
      await Future.delayed(const Duration(milliseconds: 80));
      c.showMarkerInfoWindow(MarkerId(d.id));
    } catch (_) {}
  }

  // --- 下部の選択カード + 経路 ---
  Widget _buildSelectedCard() {
    final d = _selected;
    if (d == null) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _selected = null),
                          icon: const Icon(Icons.close),
                          tooltip: '閉じる',
                        ),
                      ],
                    ),
                    if (d.workTitle.isNotEmpty || d.address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          [
                            d.workTitle,
                            d.address,
                          ].where((e) => e.isNotEmpty).join(' / '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _openRoute(d),
                          icon: const Icon(Icons.directions),
                          label: const Text('経路'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _goToLatLng(
                              LatLng(d.latitude, d.longitude),
                              zoom: _hitZoom,
                            );
                          },
                          icon: const Icon(Icons.center_focus_strong),
                          label: const Text('中心へ'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRoute(LocationData d) async {
    final lat = d.latitude;
    final lng = d.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('マップアプリを開けませんでした')));
    }
  }

  // --- AppBar ---
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: '作品名・スポット名・住所',
            prefixIcon: const Icon(Icons.search),
            suffixIcon:
                _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _showCandidates = false;
                        });
                      },
                    ),
            filled: true,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          // 入力中は候補パネルだけ出す（Firestoreには触らない）
          onChanged: (v) {
            setState(() {
              _showCandidates = v.trim().isNotEmpty;
            });
          },
          // Enterで確定→初めて地図移動
          onSubmitted: (v) => _confirmSearch(v),
          textInputAction: TextInputAction.search,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'ログアウト',
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }

  Future<void> _confirmSearch(String v) async {
    final results = _filter(_all, v);
    if (results.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('該当がありません')));
      return;
    }
    final hit = results.first;
    setState(() {
      _selected = hit;
      _showCandidates = false;
    });
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 40));
    await _goToLatLng(LatLng(hit.latitude, hit.longitude), zoom: _hitZoom);
    try {
      final c = await _controller();
      await Future.delayed(const Duration(milliseconds: 80));
      c.showMarkerInfoWindow(MarkerId(hit.id));
    } catch (_) {}
  }

  // --- ズームボタン（iOSでも表示） ---
  Widget _buildZoomButtons() {
    // 紫いろのズームボタン（白い標準ズームは無効化済み）
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          // ★ ① 右下へ配置（下の白いズームは消してある）
          padding: const EdgeInsets.only(right: 12, bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                onPressed: () async {
                  final c = await _controller();
                  final current = await c.getZoomLevel();
                  await c.animateCamera(CameraUpdate.zoomTo(current + 1));
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                onPressed: () async {
                  final c = await _controller();
                  final current = await c.getZoomLevel();
                  await c.animateCamera(CameraUpdate.zoomTo(current - 1));
                },
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ビルド ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101214), // 白フラッシュ抑制（暗め）
      appBar: _buildAppBar(),
      body: StreamBuilder<List<LocationData>>(
        // ★ ② 入力のたびに新しいStreamを作らない
        stream: _locationsStream,
        builder: (context, snap) {
          final isFirstLoad =
              snap.connectionState == ConnectionState.waiting && _all.isEmpty;
          final isUpdating =
              snap.connectionState == ConnectionState.waiting &&
              _all.isNotEmpty;

          if (isFirstLoad) {
            return Container(
              color: const Color(0xFF101214),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            );
          }

          final data = snap.data ?? _all;
          _all = data;

          final markers =
              data.map((d) {
                return Marker(
                  markerId: MarkerId(d.id),
                  position: LatLng(d.latitude, d.longitude),
                  infoWindow: InfoWindow(
                    title: d.name,
                    snippet: [
                      d.workTitle,
                      d.address,
                    ].where((e) => e.isNotEmpty).join(' / '),
                    onTap: () => setState(() => _selected = d),
                  ),
                  onTap: () => setState(() => _selected = d),
                );
              }).toSet();

          // 初回読み込み後に全体フィット
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _fitToAllIfNeeded(),
          );

          return Stack(
            children: [
              Positioned.fill(child: Container(color: const Color(0xFF101214))),
              GoogleMap(
                initialCameraPosition: _initialCamera,
                onMapCreated: (c) async {
                  if (!_mapCtrl.isCompleted) _mapCtrl.complete(c);
                  _mapReady = true;
                  await c.moveCamera(
                    CameraUpdate.newCameraPosition(_initialCamera),
                  );
                  await Future.delayed(const Duration(milliseconds: 120));
                  await _fitToAllIfNeeded();
                },
                // ★ ① パンは世界中OK
                cameraTargetBounds: CameraTargetBounds.unbounded,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                // ★ ① 下の白いズームは消す
                zoomControlsEnabled: false,
                // パン/回転/傾きは有効
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                markers: markers,
                onTap: (_) {
                  if (_showCandidates) setState(() => _showCandidates = false);
                },
              ),

              // 検索候補（地図の上に重ねる）
              _buildCandidatePanel(
                _filter(_all, _searchCtrl.text).take(20).toList(),
              ),

              // ズーム＋/−（紫）
              _buildZoomButtons(),

              // 下部の選択カード
              _buildSelectedCard(),

              // Firestoreが本当に更新中のときだけ薄くオーバーレイ
              if (isUpdating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: const Color(0x99000000),
                      alignment: Alignment.topCenter,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
