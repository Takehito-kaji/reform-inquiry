source "https://rubygems.org"

gem "rails", "~> 8.0.3"
gem "propshaft"            # CSS などを配信する仕組み
gem "puma", ">= 5.0"       # Webサーバー
gem "tzinfo-data", platforms: %i[ windows jruby ]

# 手元のパソコン（開発・テスト）では MySQL を使う。Sequel Ace で中身を確認できます
group :development, :test do
  gem "mysql2", "~> 0.5"
  gem "dotenv"             # .env ファイルから設定を読み込む
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

# Render（本番）では PostgreSQL を使う
group :production do
  gem "pg", "~> 1.1"
end

group :test do
  gem "webmock"            # Slack などへの通信を偽物に置き換える
end
