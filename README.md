# リフォーム問い合わせ受付アプリ（Ruby on Rails 版）

電話で受けたリフォームの問い合わせを入力して保存し、Slack の営業チャンネルへ自動で知らせるアプリです。

- お客様情報の入力（郵便番号から住所を自動入力）
- ご依頼内容を4ステップで入力：① 修理の依頼場所（複数選択）→ ② 問い合わせ内容（よくある内容10個＋その他から複数選択）→ ③ お客様の希望内容（リフォーム依頼／クレーム・修理依頼／見積もり依頼／その他）→ ④ その他伝達事項
- ① で選んだ場所に関係する問い合わせ内容が、② の先頭に並ぶ
- ③ で選んだ希望内容に合わせて、④ の定型文と記入例が切り替わる
- PDF の添付（図面・見積依頼書など。5個まで、1つ10MBまで）
- Slack への自動投稿（担当営業への @メンション、PDF も Slack に送れる）
- 受付履歴の一覧と検索、Slack に送れなかったときの再送

| | 手元のパソコン | Render（本番） |
|---|---|---|
| データベース | MySQL（Sequel Ace で中身を確認できる） | PostgreSQL |
| 設定の置き場所 | `.env` ファイル | Render の「Environment」画面 |
| ログイン | なし | Basic認証（ID とパスワード） |

---

## 1. 手元のパソコンで動かす

### 必要なもの

- Ruby 3.2 以上（`ruby -v` で確認）
- MySQL（今まで Sequel Ace で使っていたもの）
- Git と GitHub のアカウント

### 手順

ターミナルで、このフォルダに移動してから順に実行します。

```bash
cd ~/テックキャンプ/reform-inquiry-rails
```

**① 使う Ruby のバージョンを記録する**（Render も同じバージョンで動かすため）

```bash
ruby -e 'puts RUBY_VERSION' > .ruby-version
```

**② ライブラリを入れる**

```bash
bundle config set --local without production
bundle install
bundle lock --add-platform x86_64-linux
```

- 1行目は「本番用の PostgreSQL ライブラリは手元では入れない」という設定です
- 3行目は「Render（Linux）でも同じライブラリを使えるようにする」設定です。**これを忘れると Render でのデプロイに失敗します**

**③ 設定ファイルを作る**

```bash
cp .env.example .env
code .env
```

`DB_PASSWORD=` に MySQL のパスワード（なければ空のまま）、`SLACK_WEBHOOK_URL=` に Slack の Webhook URL を書いて上書き保存（`⌘ + S`）します。

**④ データベースを作る**

```bash
bin/rails db:create
bin/rails db:migrate
```

Sequel Ace で見ると、`reform_inquiry_development`（普段使う）と `reform_inquiry_test`（テスト用）ができています。
※ 前の Sinatra 版のデータ（`reform_inquiry`）は引き継がれません。

**⑤ 起動する**

```bash
bin/rails server
```

ブラウザで http://localhost:3000 を開きます。止めるときは `Ctrl + C`。

**⑥ テストを実行する**

```bash
bin/rails test
```

最後に `0 failures, 0 errors` と出れば合格です（121件）。テストは `reform_inquiry_test` を使うので、普段のデータは消えません。Slack や郵便番号検索には実際には送信しません。

---

## 2. GitHub に上げる

1. GitHub で新しいリポジトリを作る（名前の例：`reform-inquiry`）。中身は空のままにする
2. ターミナルで次を実行（`あなたの名前` は GitHub のユーザー名に置き換え）

```bash
git init
git add .
git commit -m "問い合わせ受付アプリ"
git branch -M main
git remote add origin https://github.com/あなたの名前/reform-inquiry.git
git push -u origin main
```

`.env`（パスワードや Slack の URL が入ったファイル）は `.gitignore` で除外してあるので、GitHub には上がりません。念のため、GitHub の画面で `.env` がないことを確認してください。`Gemfile.lock` と `.ruby-version` は上がっている必要があります。

---

## 3. Render にデプロイする

このアプリには `render.yaml`（Render の Blueprint 用の設定）が入っているので、Web アプリとデータベースをまとめて作れます。

1. https://render.com に GitHub アカウントでログインする
2. 右上の「New」→「Blueprint」を選ぶ
3. さっきのリポジトリを選んで「Connect」
4. 入力欄が出るので、次を入れて「Apply」（または「Deploy Blueprint」）

| 項目 | 入れるもの |
|---|---|
| `BASIC_AUTH_USER` | 画面を開くときの ID（自分で決める。例：`reform`） |
| `BASIC_AUTH_PASSWORD` | 画面を開くときのパスワード（自分で決める。推測されにくいもの） |
| `SLACK_WEBHOOK_URL` | Slack の Webhook URL |
| `SLACK_BOT_TOKEN` / `SLACK_CHANNEL_ID` | PDF も Slack に送る場合だけ。不要なら空欄 |

5. 最初のデプロイは 5〜10 分ほどかかります。「Live」になったら、画面上部の `https://〜.onrender.com` を開く
6. ID とパスワードを聞かれるので、4 で決めたものを入れる

`DATABASE_URL`（データベースの接続先）と `SECRET_KEY_BASE`（暗号化の鍵）は Render が自動で設定します。

### 提出するもの

- アプリの URL（`https://〜.onrender.com`）
- Basic認証の ID とパスワード（先生が画面を開くのに必要です）
- GitHub リポジトリの URL

### 直したあと

コードを直したら `git add .` → `git commit -m "変更内容"` → `git push` するだけで、Render が自動でデプロイし直します。

### Render の設定を変えるとき

Render のダッシュボードで `reform-inquiry` を開き、左の「Environment」で値を変えて「Save Changes」。自動で再起動します。

---

## 4. Render の無料プランについて（必ず読んでください）

- **15分間アクセスがないと眠ります。** 次に開いたとき、起動まで1分ほどかかります（データは消えません）
- **無料のデータベースは作成から30日で期限切れになります。** その後14日以内に有料プランにしないと、データベースごと削除されます。提出・採点の日程に間に合うように作ってください。期限が来たら、データベースを作り直せばアプリはまた動きます（データは消えます）
- **データベースの容量は 1GB です。** 添付 PDF もデータベースに保存しています（無料プランではファイル置き場が再起動のたびに消えるため）
- このアプリはインターネットに公開されます。Basic認証の ID とパスワードは他の人に教えないでください。設定し忘れた場合は、安全のため画面が開けないようにしてあります
- お客様の個人情報を本番で扱うかどうかは、会社のルールも確認してください。提出用には、架空のお客様情報で動作確認するのがおすすめです

---

## 5. Slack の設定

### Webhook URL の発行（メッセージを送る）

1. https://api.slack.com/apps で「Create New App」→「From scratch」
2. 左メニューの「Incoming Webhooks」をオンにし、「Add New Webhook to Workspace」で投稿先のチャンネルを選ぶ
3. 表示された `https://hooks.slack.com/services/...` を、`.env`（手元）と Render の `SLACK_WEBHOOK_URL` に設定

### 担当営業に @メンション する

Slack で営業マンのプロフィールを開き、「︙」→「メンバーIDをコピー」で `U012AB3CD` のような ID を取り、`config/initializers/app_settings.rb` の `SALES_SLACK_IDS` に登録します。

### PDF も Slack に送る（外出先のスマホで開ける）

1. Slack アプリの設定画面で「OAuth & Permissions」→「Bot Token Scopes」に `chat:write` と `files:write` を追加
2. 「Install to Workspace」（または「Reinstall」）を押し、**Bot User OAuth Token**（`xoxb-` で始まる）をコピー
3. 送信先チャンネルのチャンネル名をクリック → いちばん下の **チャンネルID**（`C` で始まる）をコピー
4. そのチャンネルで `/invite @アプリ名` と送り、ボットを招待
5. `SLACK_BOT_TOKEN` と `SLACK_CHANNEL_ID` を設定（2つとも設定すると、Webhook ではなくボットで送ります）

---

## 6. カスタマイズ

`config/initializers/app_settings.rb` を書き換えて、アプリを再起動（Render は `git push`）すると反映されます。

| 変えたいもの | 編集する設定 |
|---|---|
| ① 依頼場所の選択肢 | `REPAIR_LOCATIONS` |
| ② よくある問い合わせ内容と、関係する場所 | `COMMON_ISSUES` |
| ③ 希望内容の種類と説明 | `REQUEST_TYPES` |
| ④ 定型文（希望内容ごと） | `QUICK_PHRASES` |
| ④ 記入例（希望内容ごと） | `DETAIL_EXAMPLES` |
| 営業マンの名前と Slack メンバーID | `SALES_SLACK_IDS` |
| 受付する事務員の名前 | `OFFICE_STAFF` |
| 連絡希望時間帯 | `CONTACT_TIMES` |
| 添付PDFの個数・大きさの上限 | `MAX_PDF_COUNT` / `MAX_PDF_SIZE_MB` |
| イメージカラー | `app/assets/stylesheets/application.css` の `--main` |

## 7. ファイルの場所

| 場所 | 中身 |
|---|---|
| `app/models/inquiry.rb` | 問い合わせ（入力値の整形・チェック、検索） |
| `app/models/attachment.rb` | 添付PDF（形式・大きさのチェック） |
| `app/controllers/` | 画面ごとの処理（入力・保存・履歴・PDF表示・郵便番号検索・Basic認証） |
| `app/services/slack_message.rb` | Slack に送る文章づくり（メンション、記号の安全な変換） |
| `app/services/slack_notifier.rb` | Slack への送信（Webhook／ボット、エラーの日本語案内） |
| `app/views/inquiries/` | 画面（入力・詳細・履歴） |
| `db/migrate/` | テーブルの定義 |
| `test/` | テスト（モデル・Slack送信・画面操作） |
| `render.yaml`, `bin/render-build.sh` | Render 用の設定と準備手順 |

## 8. うまくいかないとき

- **Render で「Your bundle only supports platforms…」と出て失敗する** → 手元で `bundle lock --add-platform x86_64-linux` を実行し、`git add Gemfile.lock` → commit → push
- **Render で Ruby のバージョンのエラーが出る** → `.ruby-version` が GitHub に上がっているか確認。手順 1-① をやり直して push
- **`bundle install` で mysql2 がエラー** → `brew install mysql zstd` の後、`bundle config set --local build.mysql2 "--with-opt-dir=$(brew --prefix openssl) --with-ldflags=-L$(brew --prefix zstd)/lib"` を実行して再度 `bundle install`
- **`bin/rails db:create` で `Access denied`** → `.env` の `DB_USER` / `DB_PASSWORD` が Sequel Ace で接続できる情報と同じか確認
- **Render で「BASIC_AUTH_USER と BASIC_AUTH_PASSWORD を…」と表示される** → Render の「Environment」で2つとも設定する
- **Slack に届かない** → 詳細画面に赤いエラーと直し方が出ます。直したら「もう一度送る」を押してください（データは保存済みです）
- **Render のエラーの詳しい内容を見たい** → Render のダッシュボードで「Logs」を開く
