# pilgrimage_app

## What

Flutter製の巡礼支援モバイルアプリ。`lib/` 以下が主な実装で、
構成の詳細は @docs/architecture.md を参照。
状態管理は [使ってるもの: Riverpod / Provider / Bloc 等] を採用。使用していない場合は無理に使う必要はない。

## How

- 型チェック・解析: `flutter analyze`（コミット前に必須）
- テスト: `flutter test test/path/to/file_test.dart` のように
  単一ファイル指定を優先する。全体実行は避ける。
- フォーマット: `dart format` は PostToolUse Hook で自動化済み。
  Claudeから明示的に走らせる必要はない。

## Important rules

- `lib/generated/` 以下は自動生成。直接編集しない。
- 環境変数・APIキーを含むコミットは絶対にしない。
- 新規パッケージ追加時は必ず `pubspec.yaml` に
  バージョン制約を明記する（^ や >= で固定）。

## Personal preferences (optional, can move to CLAUDE.local.md)

- コミットメッセージは Conventional Commits 形式
  （feat:, fix:, refactor: ...）。
- コード内コメントは日本語OK。
