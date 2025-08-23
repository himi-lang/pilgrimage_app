// map_screen.dart — 候補だけピン表示 + Enter後は固定 + 復元 + 現在地スタート（最優先）+ ピン選択で画像プレビュー
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';
import './models/location.dart';
import 'widgets/app_ui.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // --- 検索 ---
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showCandidates = false;

  // 画像の下に説明文を（最大3行で）表示。空なら非表示。
  Widget _buildSpotDescription(LocationData d) {
    final desc = (d.description ?? '').trim();
    if (desc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        desc,
        style: const TextStyle(fontSize: 13.5, height: 1.4),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // Enterでその時点の候補集合を固定
  bool _pinsLocked = false;
  Set<String> _lockedPinIds = {};

  // --- 地図 ---
  final Completer<GoogleMapController> _mapCtrl =
      Completer<GoogleMapController>();
  bool _mapReady = false;
  bool _initialFitDone = false;
  LocationData? _selected;

  // 現在地
  LatLng? _userLatLng;
  bool _triedStartFromUser = false;

  // 中断/再開（復元用）
  CameraPosition? _resumeCamera;
  String? _resumeSelectedId;
  bool _didRestoreSelected = false;

  // カメラ追跡（保存用）
  CameraPosition? _lastCamera;

  // Firestore
  late final Stream<List<LocationData>> _locationsStream;
  List<LocationData> _all = [];

  // --- 端末保存キー ---
  static const _kLat = 'resume_lat';
  static const _kLng = 'resume_lng';
  static const _kZoom = 'resume_zoom';
  static const _kTilt = 'resume_tilt';
  static const _kBearing = 'resume_bearing';
  static const _kSearch = 'resume_search';
  static const _kSelectedId = 'resume_selected_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationsStream = FirebaseService().locationsStreamAllWorks();
    _loadResumeState(); // 先に読み出し（適用はMap作成後）
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveResumeState();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveResumeState();
    }
  }

  // 初期カメラ（日本）
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(35.681236, 139.767125),
    zoom: 5.5,
    tilt: 0,
    bearing: 0,
  );

  static const double _hitZoom = 16.0;

  // --- 文字正規化 + 検索 ---
  String _normalize(String s) {
    final runes = s
        .trim()
        .toLowerCase()
        .runes
        .map((r) {
          if (r >= 0xFF01 && r <= 0xFF5E) return r - 0xFEE0; // 全角→半角
          if (r >= 0x30A1 && r <= 0x30F6) return r - 0x60; // ｶﾅ→ひらがな
          return r;
        })
        .where((r) {
          const drops = [0x0020, 0x3000, 0x3001, 0x3002];
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

  // --- 地図操作 ---
  Future<GoogleMapController> _controller() async => _mapCtrl.future;

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

  // === 現在地 ===
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<LatLng?> _getUserLatLng() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('端末の位置情報がOFFです');
      return null;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _showSnack('位置情報の許可がありません');
      return null;
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
      );
      return LatLng(p.latitude, p.longitude);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
      return null;
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
      return null;
    }
  }

  Future<void> _startFromUserOrFit() async {
    if (_triedStartFromUser || !_mapReady) return;
    _triedStartFromUser = true;

    final loc = await _getUserLatLng();
    if (!mounted) return;

    if (loc != null) {
      _userLatLng = loc;
      _initialFitDone = true;
      await _goToLatLng(loc, zoom: 15);
      setState(() {}); // 青点の見た目更新
    } else {
      await _fitToAllIfNeeded();
    }
  }

  // === 中断/再開 ===
  Future<void> _loadResumeState() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble(_kLat);
    final lng = p.getDouble(_kLng);
    final zoom = p.getDouble(_kZoom);
    final tilt = p.getDouble(_kTilt);
    final bearing = p.getDouble(_kBearing);
    final s = p.getString(_kSearch);
    final sel = p.getString(_kSelectedId);

    if (lat != null && lng != null && zoom != null) {
      _resumeCamera = CameraPosition(
        target: LatLng(lat, lng),
        zoom: zoom,
        tilt: tilt ?? 0,
        bearing: bearing ?? 0,
      );
    }
    if (s != null) {
      _searchCtrl.text = s;
      _showCandidates = s.trim().isNotEmpty;
    }
    if (sel != null && sel.isNotEmpty) {
      _resumeSelectedId = sel;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveResumeState() async {
    final p = await SharedPreferences.getInstance();

    final cam = _lastCamera;
    if (cam != null) {
      await p.setDouble(_kLat, cam.target.latitude);
      await p.setDouble(_kLng, cam.target.longitude);
      await p.setDouble(_kZoom, cam.zoom);
      await p.setDouble(_kTilt, cam.tilt);
      await p.setDouble(_kBearing, cam.bearing);
    }
    await p.setString(_kSearch, _searchCtrl.text);

    if (_selected != null) {
      await p.setString(_kSelectedId, _selected!.id);
    } else {
      await p.remove(_kSelectedId);
    }
  }

  // ★優先度：現在地 →（ダメ）全体フィット →（まだなら）復元カメラ
  Future<void> _applyResumeOrStart() async {
    if (!_mapReady) return;

    // 1) 現在地へ（できればこれで終わり）
    await _startFromUserOrFit();
    if (_initialFitDone) return;

    // 2) 復元カメラへ（最後の保険）
    final c = await _controller();
    if (_resumeCamera != null) {
      _initialFitDone = true;
      await c.moveCamera(CameraUpdate.newCameraPosition(_resumeCamera!));
    }
  }

  LocationData? _findById(String id) {
    for (final d in _all) {
      if (d.id == id) return d;
    }
    return null;
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
      _pinsLocked = true;
      _lockedPinIds = {_selected!.id}; // タップ時はその1件に固定
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

  // =========================
  // ピン選択時の画像プレビュー（追加）
  // =========================
  bool _isValidImageUrl(String? url) {
    if (url == null) return false;
    final u = url.trim();
    if (u.isEmpty) return false;
    final uri = Uri.tryParse(u);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  void _openImageViewer(String url, String title) {
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                InteractiveViewer(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 48),
                          ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '閉じる',
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSpotImage(LocationData d) {
    final url = d.image.trim();
    if (!_isValidImageUrl(url)) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openImageViewer(url, d.name),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black12),
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                    errorBuilder: (context, error, stack) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

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
                          onPressed:
                              () => setState(() {
                                _selected = null;
                                // 固定は維持（必要なら解除の1行を有効化）
                                // _pinsLocked=false; _lockedPinIds.clear();
                              }),
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

                    // ★画像プレビューをここに差し込む（UI崩さず）
                    _buildSpotImage(d),

                    //画像の下に説明文を追加
                    _buildSpotDescription(d),

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
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${d.latitude},${d.longitude}&travelmode=walking',
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
                          _pinsLocked = false;
                          _lockedPinIds.clear();
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
          onChanged:
              (v) => setState(() {
                _showCandidates = v.trim().isNotEmpty;
                _pinsLocked = false; // 入力し直したら固定解除
              }),
          onSubmitted: (v) => _confirmSearch(v),
          textInputAction: TextInputAction.search,
        ),
      ),
      actions: const [LogoutButton()],
    );
  }

  Future<void> _confirmSearch(String v) async {
    // 現在の候補（＝画面に出ている集合）を確定・固定
    final candidates = _filter(_all, v).take(20).toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('該当がありません')));
      setState(() {
        _pinsLocked = false;
        _lockedPinIds.clear();
        _showCandidates = false;
      });
      return;
    }

    final hit = candidates.first;
    setState(() {
      _pinsLocked = true;
      _lockedPinIds = candidates.map((d) => d.id).toSet(); // ← この集合を保持
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

  Widget _buildZoomButtons() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
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
      backgroundColor: const Color(0xFF101214),
      appBar: _buildAppBar(),
      body: StreamBuilder<List<LocationData>>(
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

          // 今の入力に対する候補（パネルと同じ20件）
          final candidates = _filter(_all, _searchCtrl.text).take(20).toList();

          // 表示するピン集合を決定
          final List<LocationData> visible =
              _pinsLocked
                  ? _all.where((d) => _lockedPinIds.contains(d.id)).toList()
                  : (_showCandidates && _searchCtrl.text.trim().isNotEmpty)
                  ? candidates
                  : _all;

          final markers =
              visible
                  .map(
                    (d) => Marker(
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
                    ),
                  )
                  .toSet();

          // 1) 初回：現在地→全体→復元 の順で適用
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_mapReady) {
              await _applyResumeOrStart();
            }
            // 2) 復元で選択中スポットがあれば反映
            if (!_didRestoreSelected && _resumeSelectedId != null) {
              final d = _findById(_resumeSelectedId!);
              _didRestoreSelected = true;
              if (d != null) {
                setState(() => _selected = d);
                try {
                  final c = await _controller();
                  c.showMarkerInfoWindow(MarkerId(d.id));
                } catch (_) {}
              }
            }
          });

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
                  await _applyResumeOrStart();
                },
                cameraTargetBounds: CameraTargetBounds.unbounded,
                myLocationEnabled: true, // 青点オン
                myLocationButtonEnabled: true, // 右上ボタンもオン
                zoomControlsEnabled: false,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                markers: markers,
                onTap: (_) {
                  if (_showCandidates) setState(() => _showCandidates = false);
                },
                onCameraMove: (pos) => _lastCamera = pos,
              ),

              // 候補パネルは candidates を表示
              _buildCandidatePanel(candidates),
              _buildZoomButtons(),
              _buildSelectedCard(),

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
