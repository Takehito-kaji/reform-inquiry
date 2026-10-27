require "net/http"

# 問い合わせを Slack に送り、結果を問い合わせに記録する
#   ・SLACK_BOT_TOKEN と SLACK_CHANNEL_ID があれば、ボットでメッセージと PDF を送る
#   ・なければ、SLACK_WEBHOOK_URL でメッセージだけ送る
class SlackNotifier
  API = "https://slack.com/api/".freeze

  class ApiError < StandardError; end

  WEBHOOK_ERROR_HINTS = {
    "no_service"          => "Webhook URL が無効です。Slack アプリの設定画面で URL を確認してください",
    "invalid_token"       => "Webhook URL が無効です。Slack アプリの設定画面で URL を確認してください",
    "channel_not_found"   => "送信先チャンネルが見つかりません。削除されていないか確認してください",
    "channel_is_archived" => "送信先チャンネルがアーカイブされています",
    "action_prohibited"   => "Slack の管理者設定で送信が禁止されています",
    "invalid_payload"     => "送信内容の形式に問題があります"
  }.freeze

  BOT_ERROR_HINTS = {
    "not_in_channel"        => "ボットがチャンネルに参加していません。Slack のチャンネルで「/invite @アプリ名」を実行してください",
    "channel_not_found"     => "SLACK_CHANNEL_ID が正しくありません。チャンネルIDを確認してください",
    "invalid_auth"          => "SLACK_BOT_TOKEN が正しくありません。「xoxb-」で始まるトークンを貼り直してください",
    "not_authed"            => "SLACK_BOT_TOKEN が設定されていません",
    "token_revoked"         => "SLACK_BOT_TOKEN が無効になっています。Slack アプリを再インストールして新しいトークンを設定してください",
    "account_inactive"      => "SLACK_BOT_TOKEN が無効になっています。Slack アプリを再インストールして新しいトークンを設定してください",
    "missing_scope"         => "ボットの権限が足りません。chat:write と files:write を追加し、アプリを再インストールしてください",
    "file_type_not_allowed" => "Slack の管理者設定で、このファイルの送信が禁止されています",
    "is_archived"           => "送信先チャンネルがアーカイブされています",
    "ratelimited"           => "短時間に送りすぎました。少し待ってから「もう一度送る」を押してください"
  }.freeze

  def initialize(inquiry)
    @inquiry = inquiry
  end

  # 送って結果を記録する。成功なら true
  def deliver
    ok, error = bot_enabled? ? post_with_bot : post_with_webhook
    if ok
      @inquiry.update_columns(chat_sent: true, chat_sent_at: Time.current, chat_error: nil)
    else
      @inquiry.update_columns(chat_sent: false, chat_error: error.to_s[0, 1000])
    end
    ok
  end

  # ---- 設定の確認（問題があれば、原因と直し方を返す） ----

  def self.webhook_config_error(url)
    if url.empty?
      return "Render の「Environment」に SLACK_WEBHOOK_URL が設定されていません" if Rails.env.production?

      env_file = Rails.root.join(".env")
      unless env_file.exist?
        others = Dir.glob(Rails.root.join(".env*").to_s).map { |f| File.basename(f) } - [".env.example"]
        hint = others.empty? ? "" : "（「#{others.join('、')}」はありますが、名前を「.env」ぴったりにしてください）"
        return ".env ファイルが見つかりません。#{Rails.root} に .env.example をコピーして .env を作ってください#{hint}"
      end
      return ".env に「SLACK_WEBHOOK_URL=」の行がないか、URL が空欄です"
    end
    return "SLACK_WEBHOOK_URL が見本（XXXX）のままです。Slack で発行した URL に書き換えてください" if url.include?("XXXX")
    unless url.start_with?("https://hooks.slack.com/")
      return "SLACK_WEBHOOK_URL の形式が違います。「https://hooks.slack.com/services/」で始まる URL を設定してください"
    end
    nil
  end

  def self.bot_config_error
    token   = ENV["SLACK_BOT_TOKEN"].to_s.strip
    channel = ENV["SLACK_CHANNEL_ID"].to_s.strip
    return "SLACK_BOT_TOKEN が空欄です（PDFをSlackに送るには SLACK_CHANNEL_ID と両方必要です）" if token.empty?
    return "SLACK_CHANNEL_ID が空欄です（PDFをSlackに送るには SLACK_BOT_TOKEN と両方必要です）" if channel.empty?
    return "SLACK_BOT_TOKEN の形式が違います。「xoxb-」で始まる Bot User OAuth Token を設定してください" unless token.start_with?("xoxb-")
    return "SLACK_CHANNEL_ID の形式が違います。「C」で始まるチャンネルIDを設定してください" unless channel.match?(/\A[CG][A-Z0-9]{6,}\z/)
    nil
  end

  # 受付アプリのアドレス。Render では自動で設定される RENDER_EXTERNAL_URL を使う
  def self.base_url
    ENV["APP_BASE_URL"].presence || ENV["RENDER_EXTERNAL_URL"].presence
  end

  private

  def settings_hint
    if Rails.env.production?
      "（Render の「Environment」を直すと自動で再起動します。そのあと「もう一度送る」を押してください）"
    else
      "（.env を直したら、アプリを再起動してから「もう一度送る」を押してください）"
    end
  end

  def bot_enabled?
    ENV["SLACK_BOT_TOKEN"].present? || ENV["SLACK_CHANNEL_ID"].present?
  end

  # ---- Webhook でメッセージだけ送る ----

  def post_with_webhook
    url = ENV["SLACK_WEBHOOK_URL"].to_s.strip.delete_prefix('"').delete_suffix('"')
    problem = self.class.webhook_config_error(url)
    return [false, "#{problem}#{settings_hint}"] if problem

    text = SlackMessage.new(@inquiry, base_url: self.class.base_url).to_s
    uri  = URI(url)
    req  = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json; charset=UTF-8")
    req.body = { text: text }.to_json
    res = http(uri).request(req)
    return [true, nil] if res.is_a?(Net::HTTPSuccess)

    code = res.body.to_s.strip
    hint = WEBHOOK_ERROR_HINTS[code]
    [false, "HTTP #{res.code}: #{code[0, 200]}#{hint ? "（#{hint}）" : ''}"]
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}"]
  end

  # ---- ボットでメッセージを送り、PDF をそのスレッドに添付する ----

  def post_with_bot
    problem = self.class.bot_config_error
    return [false, "#{problem}#{settings_hint}"] if problem

    files = @inquiry.attachments.to_a
    begin
      text = SlackMessage.new(@inquiry, base_url: self.class.base_url, pdf_in_thread: files.any?).to_s
      message = api("chat.postMessage", json: { channel: channel_id, text: text })
    rescue ApiError => e
      return [false, "Slack に送れませんでした：#{bot_error_text(e.message)}"]
    end
    return [true, nil] if files.empty?

    begin
      upload_pdfs(files, message["ts"])
      [true, nil]
    rescue ApiError => e
      [false, "メッセージは届きましたが、PDFを送れませんでした：#{bot_error_text(e.message)}" \
              "（「もう一度送る」を押すと、メッセージとPDFをまとめて送り直します）"]
    end
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}"]
  end

  def upload_pdfs(files, thread_ts)
    uploaded = files.map do |file|
      ticket = api("files.getUploadURLExternal", form: { filename: file.filename, length: file.byte_size })
      uri = URI(ticket["upload_url"])
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/octet-stream"
      req.body = file.data
      res = http(uri).request(req)
      raise ApiError, "アップロード失敗 HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      { id: ticket["file_id"], title: file.filename }
    end

    api("files.completeUploadExternal", json: {
      files: uploaded, channel_id: channel_id, thread_ts: thread_ts,
      initial_comment: "No.#{@inquiry.id} の添付PDF（#{files.size}件）"
    })
  end

  # Slack の API を呼ぶ。失敗したら ApiError（エラーコード付き）
  def api(method, form: nil, json: nil)
    uri = URI("#{API}#{method}")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV['SLACK_BOT_TOKEN'].to_s.strip}"
    if json
      req["Content-Type"] = "application/json; charset=utf-8"
      req.body = json.to_json
    else
      req.set_form_data(form)
    end
    res  = http(uri).request(req)
    data = JSON.parse(res.body.to_s) rescue {}
    raise ApiError, (data["error"] || "HTTP #{res.code}") unless data["ok"]

    data
  end

  def bot_error_text(code)
    hint = BOT_ERROR_HINTS[code]
    hint ? "#{code}（#{hint}）" : code
  end

  def channel_id
    ENV["SLACK_CHANNEL_ID"].to_s.strip
  end

  def http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 30
    http
  end
end
