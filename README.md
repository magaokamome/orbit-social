# Lime2

Twitter風の操作感を持つSNS型Webアプリケーションです。

## 公開URL

https://magaokamome.github.io/orbit-social/

## 構成

- フロントエンド: GitHub Pages（静的HTML / CSS / JavaScript）
- データベース: Supabase PostgreSQL
- 認証: Supabase Auth（メールアドレス / パスワード）
- リアルタイム: Supabase Realtime（投稿、フォロー、いいね、リポスト、通知、DM）
- 画像アップロード: 無効（画像ファイルはSupabase Storageへ保存しません）

## Supabase

- Project ref: `rwcsylijgplezbtpuicn`
- Region: `ap-northeast-1`
- Plan: Free
- Project URL: `https://rwcsylijgplezbtpuicn.supabase.co`

フロントエンドには公開用の publishable key のみを設定します。secret key / service_role key はブラウザーへ絶対に配置しないでください。

## データテーブル

- `profiles`: プロフィール、Authユーザーとの紐付け
- `posts`: 投稿、返信、予約投稿、投票
- `follows`: フォロー関係
- `post_likes`, `reposts`, `bookmarks`: リアクション
- `notifications`: 通知
- `conversations`, `conversation_members`, `messages`: DM
- `lists`, `list_members`: リスト
- `muted_users`, `reports`, `poll_votes`: ミュート、通報、投票
- `trends`: トレンド一覧

公開スキーマのテーブルはRLSを有効にし、公開閲覧と本人操作をポリシーで分離しています。Auth登録時はDBトリガーでプロフィールを作成します。いいね、リポスト、フォロー、返信、DMの通知もDBトリガーで作成します。

## データの正本

アプリのデータはSupabaseを正本とします。旧来の `data.json` は削除済みで、ブラウザーの `localStorage` を投稿等の永続保存には使いません。初期データは架空のデモユーザー・投稿です。

## 無料枠を前提とした運用

- GitHub Pagesは静的ファイルのみを配信し、Actionsによるビルドを追加しません。
- Supabase Storageは使用しません。
- 画像や動画のアップロードは無効です。
- データ取得は必要なテーブルに限定し、投稿一覧は最大200件を取得します。
- Realtimeは必要なテーブルだけを購読します。
- Supabaseのsecret/service_roleキーをフロントエンドへ置きません。

## 開発・運用時の注意

Supabaseのスキーマ変更はSupabase migrationとして管理し、RLSとSecurity Advisorを確認してください。無料プランの利用量・一時停止条件・転送量などはSupabaseの最新のプラン条件を確認してください。
