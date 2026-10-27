require "test_helper"

# Slack への送信（Webhook / ボット）のテスト
class SlackNotifierWebhookTest < ActiveSupport::TestCase
  test "成功したら送信済みとして記録する" do
    i = create_inquiry
    stub_request(:post, WEBHOOK_URL)
      .with(headers: { "Content-Type" => "application/json; charset=UTF-8" }).to_return(status: 200, body: "ok")

    assert SlackNotifier.new(i).deliver
    i.reload
    assert i.chat_sent
    assert_not_nil i.chat_sent_at
    assert_nil i.chat_error
    assert_includes sent_webhook_texts.first, "No.#{i.id}"
  end

  test "Slackがエラーを返したら理由を日本語で記録する" do
    i = create_inquiry
    stub_request(:post, WEBHOOK_URL).to_return(status: 400, body: "invalid_payload")
    refute SlackNotifier.new(i).deliver
    assert_includes i.reload.chat_error, "HTTP 400"
    assert_includes i.chat_error, "形式に問題があります"
  end

  test "WebhookURLが無効なら対処方法を記録する" do
    i = create_inquiry
    stub_request(:post, WEBHOOK_URL).to_return(status: 404, body: "no_service")
    SlackNotifier.new(i).deliver
    assert_includes i.reload.chat_error, "Webhook URL が無効です"
  end

  test "通信できなかったら理由を記録する" do
    i = create_inquiry
    stub_request(:post, WEBHOOK_URL).to_timeout
    refute SlackNotifier.new(i).deliver
    assert_not_nil i.reload.chat_error
  end

  test "URLの前後の空白や引用符は取り除いて送る" do
    stub_webhook_success
    with_env("SLACK_WEBHOOK_URL" => %(  "#{WEBHOOK_URL}"  )) { assert SlackNotifier.new(create_inquiry).deliver }
  end

  test "Renderでは自動で設定されるアドレスを使ってリンクを付ける" do
    stub_webhook_success
    i = create_inquiry
    with_env("RENDER_EXTERNAL_URL" => "https://reform-inquiry.onrender.com") { SlackNotifier.new(i).deliver }
    assert_includes sent_webhook_texts.first, "<https://reform-inquiry.onrender.com/inquiries/#{i.id}|受付アプリで開く>"
  end

  test "見本のままなら送らずに直し方を記録する" do
    i = create_inquiry
    with_env("SLACK_WEBHOOK_URL" => "https://hooks.slack.com/services/XXXX/XXXX/XXXX") { SlackNotifier.new(i).deliver }
    assert_includes i.reload.chat_error, "見本（XXXX）のままです"
    assert_includes i.chat_error, "アプリを再起動"
    assert_not_requested :post, %r{slack\.com}
  end
end

# 設定ミスのときに、原因を特定して案内できるか
class SlackNotifierConfigTest < ActiveSupport::TestCase
  def with_root(dir, &block)
    Rails.stub(:root, Pathname.new(dir), &block)
  end

  test "手元で.envファイルがなければそう伝える" do
    Dir.mktmpdir do |dir|
      with_root(dir) do
        err = SlackNotifier.webhook_config_error("")
        assert_includes err, ".env ファイルが見つかりません"
        assert_includes err, dir
      end
    end
  end

  test "名前が.env.txtになっていたら教える" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env.txt"), "")
      File.write(File.join(dir, ".env.example"), "")
      with_root(dir) do
        err = SlackNotifier.webhook_config_error("")
        assert_includes err, "「.env.txt」はありますが"
        refute_includes err, ".env.example」"
      end
    end
  end

  test ".envはあるが空欄なら教える" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "SLACK_WEBHOOK_URL=")
      with_root(dir) { assert_includes SlackNotifier.webhook_config_error(""), "URL が空欄です" }
    end
  end

  test "Renderでは環境変数の設定場所を教える" do
    as_production do
      assert_includes SlackNotifier.webhook_config_error(""), "Render の「Environment」に SLACK_WEBHOOK_URL"
    end
  end

  test "SlackのURLでなければ教える" do
    assert_includes SlackNotifier.webhook_config_error("https://chat.googleapis.com/v1/spaces/AAA"), "形式が違います"
  end

  test "正しいURLなら問題なし" do
    assert_nil SlackNotifier.webhook_config_error("https://hooks.slack.com/services/T0/B0/abc")
  end

  test "ボット設定の片方だけなら足りないほうを教える" do
    with_env("SLACK_BOT_TOKEN" => "xoxb-1", "SLACK_CHANNEL_ID" => "") do
      assert_includes SlackNotifier.bot_config_error, "SLACK_CHANNEL_ID が空欄です"
    end
    with_env("SLACK_BOT_TOKEN" => "", "SLACK_CHANNEL_ID" => "C0123ABCDE") do
      assert_includes SlackNotifier.bot_config_error, "SLACK_BOT_TOKEN が空欄です"
    end
  end

  test "トークンやチャンネルIDの形式違いを教える" do
    with_env("SLACK_BOT_TOKEN" => "xoxp-user", "SLACK_CHANNEL_ID" => "C0123ABCDE") do
      assert_includes SlackNotifier.bot_config_error, "xoxb-"
    end
    with_env("SLACK_BOT_TOKEN" => "xoxb-1", "SLACK_CHANNEL_ID" => "#問い合わせ") do
      assert_includes SlackNotifier.bot_config_error, "チャンネルID"
    end
  end
end

# ボットで送る（PDFも Slack に添付する）場合
class SlackNotifierBotTest < ActiveSupport::TestCase
  TOKEN   = "xoxb-test-token"
  CHANNEL = "C0123ABCDE"
  API     = "https://slack.com/api/"
  UPLOAD  = %r{https://files\.slack\.com/upload/v1/}

  setup do
    ENV["SLACK_BOT_TOKEN"]  = TOKEN
    ENV["SLACK_CHANNEL_ID"] = CHANNEL
  end

  teardown do
    ENV["SLACK_BOT_TOKEN"]  = ""
    ENV["SLACK_CHANNEL_ID"] = ""
  end

  def slack_ok(extra = {})
    { status: 200, headers: { "Content-Type" => "application/json" }, body: { ok: true }.merge(extra).to_json }
  end

  def slack_error(code)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: { ok: false, error: code }.to_json }
  end

  def stub_slack_all_ok
    n = 0
    stub_request(:post, "#{API}chat.postMessage").to_return(slack_ok(ts: "1700000000.000100"))
    stub_request(:post, "#{API}files.getUploadURLExternal").to_return do
      n += 1
      slack_ok(upload_url: "https://files.slack.com/upload/v1/abc#{n}", file_id: "F00#{n}")
    end
    stub_request(:post, UPLOAD).to_return(status: 200, body: "OK - 123")
    stub_request(:post, "#{API}files.completeUploadExternal").to_return(slack_ok(files: []))
  end

  def with_pdfs(*names)
    i = create_inquiry
    names.each_with_index do |name, n|
      content = pdf_content("#{n}")
      i.attachments.create!(filename: name, data: content, byte_size: content.bytesize)
    end
    i
  end

  test "Webhookではなくボットで送る" do
    stub_slack_all_ok
    i = create_inquiry
    assert SlackNotifier.new(i).deliver

    assert_requested(:post, "#{API}chat.postMessage", times: 1) do |req|
      body = JSON.parse(req.body)
      req.headers["Authorization"] == "Bearer #{TOKEN}" && body["channel"] == CHANNEL &&
        body["text"].include?("新規リフォーム問い合わせ")
    end
    assert_not_requested :post, WEBHOOK_URL
    assert_not_requested :post, "#{API}files.completeUploadExternal"
  end

  test "PDFをメッセージのスレッドに添付する" do
    stub_slack_all_ok
    i = with_pdfs("見積依頼書.pdf", "図面.pdf")
    assert SlackNotifier.new(i).deliver

    assert_requested(:post, "#{API}chat.postMessage") do |req|
      JSON.parse(req.body)["text"].include?("このメッセージのスレッドに添付しています")
    end
    assert_requested(:post, "#{API}files.getUploadURLExternal", times: 2)
    assert_requested(:post, "#{API}files.getUploadURLExternal") do |req|
      form = URI.decode_www_form(req.body).to_h
      form["filename"] == "見積依頼書.pdf" && form["length"] == pdf_content("0").bytesize.to_s
    end
    assert_requested(:post, "https://files.slack.com/upload/v1/abc1") { |req| req.body.b == pdf_content("0") }
    assert_requested(:post, "#{API}files.completeUploadExternal", times: 1) do |req|
      body = JSON.parse(req.body)
      body["channel_id"] == CHANNEL && body["thread_ts"] == "1700000000.000100" &&
        body["files"] == [{ "id" => "F001", "title" => "見積依頼書.pdf" }, { "id" => "F002", "title" => "図面.pdf" }] &&
        body["initial_comment"] == "No.#{i.id} の添付PDF（2件）"
    end
  end

  test "担当営業へのメンションも付く" do
    stub_slack_all_ok
    with_setting(:SALES_SLACK_IDS, { "山田" => "U012AB3CD" }) { SlackNotifier.new(create_inquiry).deliver }
    assert_requested(:post, "#{API}chat.postMessage") { |req| JSON.parse(req.body)["text"].start_with?("<@U012AB3CD>\n") }
  end

  test "ボットがチャンネルにいなければ招待方法を案内する" do
    stub_request(:post, "#{API}chat.postMessage").to_return(slack_error("not_in_channel"))
    i = create_inquiry
    refute SlackNotifier.new(i).deliver
    assert_includes i.reload.chat_error, "/invite"
  end

  test "トークンが違えば案内する" do
    stub_request(:post, "#{API}chat.postMessage").to_return(slack_error("invalid_auth"))
    i = create_inquiry
    SlackNotifier.new(i).deliver
    assert_includes i.reload.chat_error, "SLACK_BOT_TOKEN が正しくありません"
  end

  test "権限が足りなければ案内する" do
    stub_slack_all_ok
    stub_request(:post, "#{API}files.getUploadURLExternal").to_return(slack_error("missing_scope"))
    i = with_pdfs("見積.pdf")
    refute SlackNotifier.new(i).deliver
    assert_includes i.reload.chat_error, "メッセージは届きましたが、PDFを送れませんでした"
    assert_includes i.chat_error, "files:write"
  end

  test "PDFのアップロードに失敗しても再送できる" do
    stub_slack_all_ok
    stub_request(:post, UPLOAD).to_return(status: 500).then.to_return(status: 200, body: "OK")
    i = with_pdfs("見積.pdf")
    refute SlackNotifier.new(i).deliver
    assert SlackNotifier.new(i).deliver
    assert i.reload.chat_sent
    assert_nil i.chat_error
  end

  test "設定の形式に問題があればSlackに送らない" do
    with_env("SLACK_BOT_TOKEN" => "間違い") do
      i = create_inquiry
      SlackNotifier.new(i).deliver
      assert_includes i.reload.chat_error, "形式が違います"
    end
    assert_not_requested :post, %r{slack\.com}
  end
end
