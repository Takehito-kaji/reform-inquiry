require_relative "boot"

require "rails"
# このアプリで使う Rails の機能だけを読み込む
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module ReformInquiry
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "Tokyo"
    config.active_record.default_timezone = :utc
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [:ja, :en]

    # 入力ミスがあった欄を <div> で囲まない（画面の並びが崩れないように）
    config.action_view.field_error_proc = proc { |html_tag, _instance| html_tag }

    config.generators.system_tests = nil
  end
end
