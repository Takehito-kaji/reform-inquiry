require "active_support/core_ext/integer/time"

# Render（本番）での設定
Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store

  # CSS などは Rails から配信する（Render ではこれが必要）
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Render は HTTPS で公開されるので、HTTP で来たら HTTPS に転送する
  # （Render の動作確認用アドレス /up だけは転送しない）
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # ログは Render の「Logs」画面で見られるように標準出力へ
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false
  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
