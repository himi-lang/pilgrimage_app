import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/auth_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_cropper/image_cropper.dart';
import '../mode_selection_screen.dart';
import '../app_routes.dart';

//ここでは、共通するUIのパーツを作成している。

enum AppMode { map, versus }

class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed:
          onPressed ?? () => Navigator.of(context).maybePop(), //null合体演算子。
      child: const Icon(CupertinoIcons.back, color: CupertinoColors.white),
    );
  }
}

class ModeSwitchButton extends StatelessWidget {
  //appBarにある、押すと最初のマップor対戦モード選択に戻る。
  // AppMode は互換性のため残しておくだけで、今回の挙動では使わない
  final AppMode currentMode;
  // ルーム離脱時の確認・後処理はそのまま使えるように残しておく
  final Future<bool> Function()? confirm;
  final Future<void> Function()? beforeNavigate;

  const ModeSwitchButton({
    super.key,
    required this.currentMode,
    this.confirm,
    this.beforeNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        // ルームから出るときの確認をしたい画面では、これまで通り confirm/beforeNavigate が使える
        if (confirm != null) {
          final ok = await confirm!();
          if (!ok) return;
        }
        if (beforeNavigate != null) {
          await beforeNavigate!();
        }

        if (!context.mounted) return;

        // ★ モード選択画面に戻る
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const ModeSelectionScreen()),
          (route) => false, // それ以前の画面スタックを全部クリア
        );
      },
      minimumSize: Size(30, 30),
      child: const Icon(
        CupertinoIcons.square_grid_2x2,
        color: CupertinoColors.white,
      ),
    );
  }
}

class MapCornerShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const MapCornerShortcutButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: const Color(0xFF1E456E)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF1F2A37),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VisitedRecordShortcut extends StatelessWidget {
  final Alignment alignment;
  final EdgeInsets minimumPadding;
  final bool safeAreaTop;
  final bool safeAreaRight;
  final bool safeAreaBottom;
  final bool safeAreaLeft;

  const VisitedRecordShortcut({
    super.key,
    this.alignment = Alignment.bottomLeft,
    this.minimumPadding = const EdgeInsets.only(left: 12, bottom: 20),
    this.safeAreaTop = true,
    this.safeAreaRight = true,
    this.safeAreaBottom = true,
    this.safeAreaLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: safeAreaTop,
      right: safeAreaRight,
      bottom: safeAreaBottom,
      left: safeAreaLeft,
      minimum: minimumPadding,
      child: Align(
        alignment: alignment,
        child: MapCornerShortcutButton(
          icon: CupertinoIcons.check_mark_circled_solid,
          label: '制覇記録',
          onPressed: () {
            Navigator.of(context).pushNamed(AppRoutes.visitedSpots);
          },
        ),
      ),
    );
  }
}

/// 共通AppBar（右端：モード切替 → 追加actions → ログアウト）
ObstructingPreferredSizeWidget commonAppBar(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<Widget> actionsExtra = const [],
  AppMode? currentMode,
  Future<bool> Function()? modeConfirm,
  Future<void> Function()? modeBeforeNavigate,
}) {
  final resolvedLeading =
      leading ??
      (Navigator.of(context).canPop() ? const AppBackButton() : null);

  final trailingChildren = <Widget>[
    if (currentMode != null)
      ModeSwitchButton(
        currentMode: currentMode,
        confirm: modeConfirm,
        beforeNavigate: modeBeforeNavigate,
      ),
    ...actionsExtra,
    const AppMenuButton(),
  ];

  return CupertinoNavigationBar(
    automaticallyImplyLeading: false,
    leading: resolvedLeading,
    middle: Text(title, style: const TextStyle(color: CupertinoColors.white)),
    backgroundColor: Theme.of(context).colorScheme.primary,
    automaticBackgroundVisibility: false,
    trailing: Row(mainAxisSize: MainAxisSize.min, children: trailingChildren),
  );
}

/// 共通ハンバーガーメニュー
class AppMenuButton extends StatelessWidget {
  //AppBarのハンバーガーメニュー
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _openAppMenu(context),
      minimumSize: Size(30, 30),
      child: const Icon(
        CupertinoIcons.line_horizontal_3,
        color: CupertinoColors.white,
      ),
    );
  }
}

// ==== メニュー中身 ====
const _appVersion = '1.0.0+1'; //ここでアプリのバージョンを変更していく。
const _menuListTextStyle = TextStyle(
  color: CupertinoColors.black,
  decoration: TextDecoration.none,
);

class _PolicyMenuItem {
  final String title;
  final IconData icon;
  final String assetPath;

  const _PolicyMenuItem({
    required this.title,
    required this.icon,
    required this.assetPath,
  });
}

const _policyMenuItems = <_PolicyMenuItem>[
  _PolicyMenuItem(
    title: '利用規約',
    icon: Icons.description_outlined,
    assetPath: 'assets/information/Terms_of_use.txt',
  ),
  _PolicyMenuItem(
    title: 'プライバシーポリシー',
    icon: Icons.privacy_tip_outlined,
    assetPath: 'assets/information/privacy_policy.txt',
  ),
  _PolicyMenuItem(
    title: '特定商取引法',
    icon: Icons.article_outlined,
    assetPath: 'assets/information/Commercial_Transactions.txt',
  ),
  _PolicyMenuItem(
    title: '著作権',
    icon: Icons.copyright,
    assetPath: 'assets/information/Copyright.txt',
  ),
  _PolicyMenuItem(
    title: 'お問い合わせ',
    icon: Icons.mail,
    assetPath: 'assets/information/info.txt',
  ),
  _PolicyMenuItem(
    title: '注意事項',
    icon: Icons.note,
    assetPath: 'assets/information/note.txt',
  ),
];

ListTile _menuActionTile({
  required IconData icon,
  required String title,
  String? subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title, style: _menuListTextStyle),
    subtitle:
        subtitle == null ? null : Text(subtitle, style: _menuListTextStyle),
    onTap: onTap,
  );
}

//ここはハンバーガーメニューの中身の記述
void _openAppMenu(BuildContext outerContext) {
  //outerは画面側のcontext
  showModalBottomSheet(
    context: outerContext,
    useSafeArea: true,
    isScrollControlled: true, // ★ 追加：シートを大きくできるようにする
    showDragHandle: true,
    builder: (_) {
      //sheetContextはボトムシート側のcontext
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9, // 開いたときの高さ（画面の 90%）
        minChildSize: 0.3, // 一番小さいとき
        maxChildSize: 0.9, // 一番大きくドラッグしたとき（90% まで広がる）
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '設定',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              _menuActionTile(
                icon: Icons.person,
                title: 'プロフィール編集',
                subtitle: '表示名・アイコンURLを変更',
                onTap: () => _showProfileDialog(outerContext),
              ),
              _menuActionTile(
                icon: Icons.logout,
                title: 'ログアウト',
                onTap: () => AuthService.signOutAndGoRoot(outerContext),
              ),
              const Divider(height: 24),

              // 利用規約 / プライバシー / 特商法
              ..._policyMenuItems.map(
                (item) => _policyTile(
                  context,
                  title: item.title,
                  icon: item.icon,
                  assetPath: item.assetPath,
                ),
              ),

              // バージョン情報
              _menuActionTile(
                icon: Icons.info_outline,
                title: 'バージョン情報',
                subtitle: 'アプリのバージョンを表示',
                onTap: () {
                  _openInfoPage(
                    outerContext,
                    title: 'バージョン情報',
                    body: '現在のバージョン: $_appVersion',
                  );
                },
              ),

              // ★ ここから追加分 ↓↓↓
              //ListTile(
              //  leading: const Icon(Icons.copyright),
              //  title: const Text('著作権'),
              //  subtitle: const Text('コンテンツの権利者表記'),
              //  onTap: () {
              //    _openInfoPage(
              //      outerContext,
              //      title: '著作権',
              //      body:
              //          '© 2025 pilgrimage_app\n'
              //          '画像・データ等の著作権表記はここに記載します。',
              //   );
              //  },
              //),
              //ListTile(
              //  leading: const Icon(Icons.mail_outline),
              //  title: const Text('お問い合わせ'),
              //  subtitle: const Text('メールアドレスは後で追加します'),
              //  onTap: () {
              //    _openInfoPage(
              //      outerContext,
              //      title: 'お問い合わせ',
              //     body: 'お問い合わせ用のメールアドレスを後で掲載します。',
              //    );
              //  },
              //),
              const SizedBox(height: 12),
            ],
          );
        },
      );
    },
  );
}

ListTile _policyTile(
  BuildContext context, {
  required String title,
  required IconData icon,
  String? assetPath,
  String? placeholder,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title, style: _menuListTextStyle),
    subtitle: Text(
      assetPath != null ? 'タップして内容を表示' : (placeholder ?? '内容は後で追加されます'),
      style: _menuListTextStyle,
    ),
    onTap: () async {
      String body;

      if (assetPath != null) {
        try {
          body = await rootBundle.loadString(assetPath);
        } catch (e) {
          body = '内容の読み込みに失敗しました。\n\n$e';
        }
      } else {
        body = placeholder ?? '';
      }

      if (!context.mounted) return;
      _openInfoPage(context, title: title, body: body);
    },
  );
}

void _openInfoPage(
  BuildContext context, {
  required String title,
  required String body,
}) {
  Navigator.of(context).push(
    CupertinoPageRoute(builder: (_) => _InfoPage(title: title, body: body)),
  );
}

class _InfoPage extends StatelessWidget {
  final String title;
  final String body;
  const _InfoPage({required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop() ? const AppBackButton() : null,
        middle: Text(
          title,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        automaticBackgroundVisibility: false,
      ),
      child: SafeArea(
        child: CupertinoScrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: CupertinoColors.black,
                decoration: TextDecoration.none,
                decorationColor: CupertinoColors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showProfileDialog(BuildContext outerContext) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(
      outerContext,
    ).showSnackBar(const SnackBar(content: Text('ユーザー情報を取得できませんでした')));
    return;
  }

  final nameCtrl = TextEditingController(text: user.displayName ?? '');
  final formKey = GlobalKey<FormState>();

  File? localImageFile; // このダイアログ内で選んだ画像
  String? currentUrl = user.photoURL; // 既存のアイコンURL（あれば表示に使う）
  bool uploading = false;

  await showDialog(
    context: outerContext,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          // 画像を選択してトリミング
          Future<void> pickAndCrop() async {
            //プロフィールの画像を編集するところ
            final picker = ImagePicker();
            final picked = await picker.pickImage(source: ImageSource.gallery);
            if (picked == null) return;

            final cropped = await ImageCropper().cropImage(
              sourcePath: picked.path,
              // 画像自体は正方形で固定
              aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
              uiSettings: [
                AndroidUiSettings(
                  toolbarTitle: 'アイコンを切り抜き',
                  toolbarColor: Colors.black87, // 上のバーの色
                  toolbarWidgetColor: Colors.white, // × / ✅ の色
                  initAspectRatio: CropAspectRatioPreset.square,
                  lockAspectRatio: true,
                  cropStyle: CropStyle.circle, // ★ 丸い枠
                  aspectRatioPresets: const [
                    CropAspectRatioPreset.square, // メニューは square だけ
                  ],
                  hideBottomControls: false, // 下のボタンはそのまま表示
                  showCropGrid: true,
                ),
                IOSUiSettings(
                  title: 'アイコンを切り抜き',
                  cropStyle: CropStyle.circle, // ★ iOS も丸
                  aspectRatioLockEnabled: true,
                  aspectRatioPresets: const [CropAspectRatioPreset.square],
                ),
              ],
            );

            if (cropped == null) return;

            setState(() {
              // CroppedFile → File にしてダイアログのプレビューに使う
              localImageFile = File(cropped.path);
            });
          }

          // 保存処理
          Future<void> save() async {
            if (!formKey.currentState!.validate()) return;

            setState(() => uploading = true);

            String? iconUrl = currentUrl;

            // ローカルで新しい画像を選んでいればアップロード
            if (localImageFile != null) {
              final ref = FirebaseStorage.instance.ref().child(
                'user_icons/${user.uid}.jpg',
              );

              await ref.putFile(localImageFile!);
              iconUrl = await ref.getDownloadURL();
            }

            final name = nameCtrl.text.trim();

            await user.updateDisplayName(name.isEmpty ? null : name);
            await user.updatePhotoURL(iconUrl);
            await user.reload();

            if (!dialogContext.mounted) return;

            setState(() => uploading = false);

            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(const SnackBar(content: Text('プロフィールを更新しました')));
          }

          // アイコンのプレビュー用 ImageProvider
          ImageProvider? avatarImage;
          if (localImageFile != null) {
            avatarImage = FileImage(localImageFile!);
          } else if ((currentUrl ?? '').isNotEmpty) {
            avatarImage = NetworkImage(currentUrl!);
          }

          return AlertDialog(
            title: const Text('プロフィール編集'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: uploading ? null : pickAndCrop,
                    child: CircleAvatar(
                      radius: 36,
                      backgroundImage: avatarImage,
                      child:
                          avatarImage == null
                              ? const Icon(Icons.person, size: 40)
                              : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: uploading ? null : pickAndCrop,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('画像を選択'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '表示名'),
                    maxLength: 30,
                  ),
                  if (uploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    uploading ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: uploading ? null : save,
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
}
