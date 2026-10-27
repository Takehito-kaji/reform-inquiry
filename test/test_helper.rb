ENV["RAILS_ENV"] ||= "test"

# テスト中は本物の Slack 設定を使わない（必要なテストで個別に設定する）
ENV["SLACK_WEBHOOK_URL"]   = "https://hooks.slack.com/services/T000TEST/B000TEST/testsecret"
ENV["SLACK_BOT_TOKEN"]     = ""
ENV["SLACK_CHANNEL_ID"]    = ""
ENV["APP_BASE_URL"]        = ""
ENV["RENDER_EXTERNAL_URL"] = ""
ENV["BASIC_AUTH_USER"]     = ""
ENV["BASIC_AUTH_PASSWORD"] = ""

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "minitest/mock"

WEBHOOK_URL = ENV["SLACK_WEBHOOK_URL"]

module TestHelpers
  # テスト用のPDF（本物のPDFと同じく「%PDF-」で始まる中身）
  def pdf_content(text = "見積依頼書")
    "%PDF-1.4\n% #{text}\n%%EOF\n".b
  end

  # フォームから送られるファイルを作る
  def upload(name, content = pdf_content, type = "application/pdf")
    Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)
  end

  # 正しく入力されたフォームの値（テストごとに一部だけ書き換えて使う）
  def valid_params(overrides = {})
    {
      received_by:      "事務A",
      customer_name:    "山本 花子",
      customer_kana:    "ヤマモト ハナコ",
      phone:            "090-1234-5678",
      postal_code:      "460-0001",
      address:          "愛知県名古屋市中区三の丸1-1",
      location_list:    %w[トイレ 洗面所],
      issue_list:       %w[トイレが水漏れしている],
      request_type:     "クレーム・修理依頼",
      detail:           "2階トイレの床から水がにじんでいる",
      urgency:          "通常",
      contact_time:     "午前中",
      sales_person:     "山田"
    }.merge(overrides)
  end

  # DB に 1 件登録しておく
  def create_inquiry(attrs = {})
    Inquiry.create!({
      received_by: "事務A", customer_name: "山本 花子", phone: "090-1234-5678",
      address: "愛知県名古屋市中区三の丸1-1", location_list: %w[トイレ], request_type: "クレーム・修理依頼", urgency: "通常",
      sales_person: "山田"
    }.merge(attrs))
  end

  # Slack（Webhook）への送信を「成功」として偽装する（Slack は成功すると ok と返す）
  def stub_webhook_success
    stub_request(:post, WEBHOOK_URL).to_return(status: 200, body: "ok")
  end

  # Webhook に送られた本文（text）を取り出す
  def sent_webhook_texts
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys
      .select { |sig| sig.method == :post && sig.uri.host == "hooks.slack.com" }
      .map { |sig| JSON.parse(sig.body)["text"] }
  end

  # app_settings.rb の設定を一時的に書き換えてテストし、終わったら元に戻す
  def with_setting(name, value)
    original = AppSettings.const_get(name)
    AppSettings.send(:remove_const, name)
    AppSettings.const_set(name, value)
    yield
  ensure
    AppSettings.send(:remove_const, name)
    AppSettings.const_set(name, original)
  end

  # 環境変数を一時的に書き換える（nil は「その項目がない」状態）
  def with_env(vars)
    original = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # Rails.env を一時的に本番扱いにする
  def as_production(&block)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production"), &block)
  end
end

module ActiveSupport
  class TestCase
    include TestHelpers
    setup { WebMock.reset! }
  end
end

class ActionDispatch::IntegrationTest
  include TestHelpers
end
