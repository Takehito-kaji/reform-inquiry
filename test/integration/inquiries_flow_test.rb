require "test_helper"

# 画面の操作（入力 → 保存 → Slack 送信）を通しで確認する
class InquiriesFlowTest < ActionDispatch::IntegrationTest
  def submit(overrides = {})
    post inquiries_path, params: { inquiry: valid_params(overrides) }
  end

  test "トップを開くと入力画面が出る" do
    get root_path
    assert_response :success
    assert_select "form#inquiry-form[enctype='multipart/form-data']"
  end

  test "入力画面に依頼場所・問い合わせ内容・希望内容・担当営業・定型文の選択肢がすべて並ぶ" do
    get new_inquiry_path
    AppSettings.all_locations.each { |place| assert_select "input[type=checkbox][name='inquiry[location_list][]'][value=?]", place }
    AppSettings::COMMON_ISSUES.each do |issue, places|
      assert_select "label.issue[data-places=?] input[type=checkbox][name='inquiry[issue_list][]'][value=?]", places.join(","), issue
    end
    AppSettings.request_types.each { |type| assert_select "input[type=radio][name='inquiry[request_type]'][value=?]", type }
    AppSettings.sales_people.each { |name| assert_select "select[name='inquiry[sales_person]'] option", text: name }
    AppSettings::QUICK_PHRASES.each do |type, phrases|
      phrases.each { |phrase| assert_select "button.phrase[data-text=?][data-type=?]", phrase, type }
    end
    assert_select "input[type=file][name='inquiry[attachments][]'][multiple][accept='application/pdf,.pdf']"
  end

  test "保存してSlackに送り、詳細画面へ移動する" do
    stub_webhook_success
    assert_difference -> { Inquiry.count }, 1 do
      submit
    end
    saved = Inquiry.last
    assert_redirected_to inquiry_path(saved, from: "new")
    assert_equal "トイレ、洗面所", saved.locations
    assert_equal "クレーム・修理依頼", saved.request_type
    assert_equal "トイレが水漏れしている", saved.issues
    assert saved.chat_sent
    assert_includes sent_webhook_texts.first, "No.#{saved.id}"

    follow_redirect!
    assert_select ".alert-ok", text: /保存して Slack に送りました/
  end

  test "担当営業にメンション付きで送る" do
    stub_webhook_success
    with_setting(:SALES_SLACK_IDS, { "山田" => "U012AB3CD" }) { submit(sales_person: "山田") }
    assert sent_webhook_texts.first.start_with?("<@U012AB3CD>\n")
  end

  test "受付者を覚えて、次の入力画面で選んでおく" do
    stub_webhook_success
    submit(received_by: "事務C")
    get new_inquiry_path
    assert_select "select[name='inquiry[received_by]'] option[selected]", text: "事務C"
  end

  test "入力に不備があれば保存も送信もせず、入力内容は残す" do
    assert_no_difference -> { Inquiry.count } do
      submit(customer_name: "", phone: "")
    end
    assert_response :unprocessable_entity
    assert_select ".alert-error", text: /お客様の氏名を入力してください/
    assert_select ".alert-error", text: /電話番号を入力してください/
    assert_select "input[name='inquiry[address]'][value=?]", "愛知県名古屋市中区三の丸1-1"
    assert_select "input[type=checkbox][value='トイレ'][checked]"
    assert_select "input[type=radio][value='クレーム・修理依頼'][checked]"
    assert_select "input[type=checkbox][value='トイレが水漏れしている'][checked]"
    assert_not_requested :post, WEBHOOK_URL
  end

  test "Slackに送れなくてもデータは保存され、再送ボタンが出る" do
    stub_request(:post, WEBHOOK_URL).to_return(status: 500, body: "server error")
    submit
    saved = Inquiry.last
    refute saved.chat_sent
    assert_includes saved.chat_error, "HTTP 500"

    follow_redirect!
    assert_select ".alert-error", text: /Slack に送れませんでした/
    assert_select "form[action=?] button", resend_inquiry_path(saved), text: "もう一度送る"
  end

  test "もう一度送るで再送し、送信済みになる" do
    i = create_inquiry(chat_sent: false, chat_error: "HTTP 500")
    stub_webhook_success
    post resend_inquiry_path(i)
    assert_redirected_to inquiry_path(i)
    assert i.reload.chat_sent
    assert_nil i.chat_error
  end

  test "存在しない受付は404" do
    get inquiry_path(id: 999_999)
    assert_response :not_found
    post resend_inquiry_path(id: 999_999)
    assert_response :not_found
  end

  test "入力内容のHTMLはそのまま表示されない" do
    stub_webhook_success
    submit(customer_name: "<b>悪意</b>")
    follow_redirect!
    assert_no_match "<b>悪意</b>", response.body
    assert_includes response.body, "&lt;b&gt;悪意"
  end

  test "受付履歴は新しい順に並び、未送信がわかる" do
    create_inquiry(customer_name: "古い客", chat_sent: true)
    create_inquiry(customer_name: "新しい客", chat_sent: false)
    get inquiries_path
    assert response.body.index("新しい客") < response.body.index("古い客")
    assert_select ".badge-err", text: "未送信"
  end

  test "受付履歴を検索できる" do
    create_inquiry(customer_name: "伊藤 次郎")
    create_inquiry(customer_name: "加藤 三郎")
    get inquiries_path, params: { q: "伊藤" }
    assert_includes response.body, "伊藤 次郎"
    refute_includes response.body, "加藤 三郎"
  end

  test "受付がないとき・見つからないときは案内を出す" do
    get inquiries_path
    assert_includes response.body, "まだ受付がありません"
    create_inquiry
    get inquiries_path, params: { q: "該当なし" }
    assert_includes response.body, "該当する受付はありません"
  end
end

# PDF添付
class AttachmentsFlowTest < ActionDispatch::IntegrationTest
  def submit_with(*files, **overrides)
    stub_webhook_success
    post inquiries_path, params: { inquiry: valid_params(overrides).merge(attachments: files) }
  end

  test "PDFを複数添付して保存できる" do
    submit_with(upload("見積依頼書.pdf", pdf_content("A")), upload("図面.pdf", pdf_content("B")))
    rows = Inquiry.last.attachments
    assert_equal %w[見積依頼書.pdf 図面.pdf], rows.map(&:filename)
    assert_equal pdf_content("A"), rows.first.data.b
  end

  test "Slackに添付PDFのファイル名を載せる" do
    submit_with(upload("見積依頼書.pdf"), upload("図面.pdf"))
    assert_includes sent_webhook_texts.first, "*添付PDF*（2件）：見積依頼書.pdf、図面.pdf"
  end

  test "PDFでないファイルなら何も保存しない" do
    assert_no_difference ["Inquiry.count", "Attachment.count"] do
      submit_with(upload("写真.jpg", "JPEGDATA", "image/jpeg"))
    end
    assert_response :unprocessable_entity
    assert_select ".alert-error", text: /「写真.jpg」はPDFファイルではありません/
    assert_not_requested :post, WEBHOOK_URL
  end

  test "ほかの入力に不備があればPDFを選び直すよう案内する" do
    submit_with(upload("見積.pdf"), customer_name: "")
    assert_select ".alert-error", text: /添付するPDFは、もう一度選び直してください/
    assert_equal 0, Attachment.count
  end

  test "添付なしで不備があるときは選び直しの案内を出さない" do
    post inquiries_path, params: { inquiry: valid_params(customer_name: "") }
    refute_includes response.body, "選び直してください"
  end

  test "PDFの保存に途中で失敗したら問い合わせも保存しない" do
    # 2つ目のPDFを保存するときに、データベースのエラーが起きたことにする
    calls = 0
    original = Attachment.instance_method(:_create_record)
    Attachment.define_method(:_create_record) do |*args|
      calls += 1
      raise ActiveRecord::StatementInvalid, "ディスクがいっぱい" if calls == 2
      original.bind(self).call(*args)
    end

    assert_no_difference ["Inquiry.count", "Attachment.count"] do
      assert_raises(ActiveRecord::StatementInvalid) { submit_with(upload("1.pdf"), upload("2.pdf")) }
    end
    assert_equal 2, calls
    assert_not_requested :post, WEBHOOK_URL
  ensure
    Attachment.send(:remove_method, :_create_record)
  end

  test "詳細画面に添付PDFのリンクと大きさを表示し、開ける" do
    submit_with(upload("見積依頼書.pdf", pdf_content("中身")))
    file = Attachment.last
    get inquiry_path(file.inquiry)
    assert_select "a[href=?]", attachment_path(file), text: /見積依頼書.pdf/
    assert_includes response.body, "1KB"

    get attachment_path(file)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal pdf_content("中身"), response.body.b
    disposition = response.headers["Content-Disposition"]
    assert disposition.start_with?("inline")
    assert_includes disposition, "filename*=UTF-8''#{ERB::Util.url_encode('見積依頼書.pdf')}"
  end

  test "添付がない受付は詳細画面になしと表示する" do
    get inquiry_path(create_inquiry)
    assert_select "dl.detail dd", text: /\Aなし\z/
  end

  test "存在しない添付は404" do
    get attachment_path(id: 999_999)
    assert_response :not_found
  end

  test "受付履歴に添付の数を表示する" do
    submit_with(upload("1.pdf"), upload("2.pdf"))
    get inquiries_path
    assert_select ".badge-file", text: "📄2"
  end
end

# 郵便番号からの住所検索
class ZipcodesTest < ActionDispatch::IntegrationTest
  ZIPCLOUD = %r{https://zipcloud\.ibsnet\.co\.jp/api/search}

  def stub_found
    stub_request(:get, ZIPCLOUD).with(query: { zipcode: "4600001" }).to_return(
      body: { results: [{ address1: "愛知県", address2: "名古屋市中区", address3: "三の丸" }] }.to_json
    )
  end

  test "郵便番号から住所を返す" do
    stub_found
    get zipcode_path, params: { code: "460-0001" }
    assert_response :success
    assert_equal "愛知県名古屋市中区三の丸", response.parsed_body["address"]
  end

  test "全角の郵便番号でも検索できる" do
    stub_found
    get zipcode_path, params: { code: "４６０－０００１" }
    assert_response :success
  end

  test "桁数が違えば検索しない" do
    get zipcode_path, params: { code: "460" }
    assert_response :bad_request
    assert_not_requested :get, ZIPCLOUD
  end

  test "該当がなければ404" do
    stub_request(:get, ZIPCLOUD).to_return(body: { results: nil }.to_json)
    get zipcode_path, params: { code: "0000000" }
    assert_response :not_found
    assert_includes response.parsed_body["error"], "見つかりません"
  end

  test "住所検索サービスが落ちていても手入力を案内する" do
    stub_request(:get, ZIPCLOUD).to_timeout
    get zipcode_path, params: { code: "4600001" }
    assert_response :bad_gateway
    assert_includes response.parsed_body["error"], "手入力"
  end
end

# Basic認証（ID とパスワードを知っている人だけが開ける）
class BasicAuthTest < ActionDispatch::IntegrationTest
  def auth(user, pass)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  test "設定したら、正しいIDとパスワードでだけ開ける" do
    with_env("BASIC_AUTH_USER" => "admin", "BASIC_AUTH_PASSWORD" => "secret") do
      get new_inquiry_path
      assert_response :unauthorized

      get new_inquiry_path, headers: auth("admin", "wrong")
      assert_response :unauthorized

      get new_inquiry_path, headers: auth("admin", "secret")
      assert_response :success
    end
  end

  test "添付PDFや住所検索も守られる" do
    with_env("BASIC_AUTH_USER" => "admin", "BASIC_AUTH_PASSWORD" => "secret") do
      get attachment_path(id: 1)
      assert_response :unauthorized
      get zipcode_path, params: { code: "4600001" }
      assert_response :unauthorized
    end
  end

  test "本番で設定し忘れていたら画面を開けなくする" do
    as_production do
      get new_inquiry_path
      assert_response :service_unavailable
      assert_includes response.body, "BASIC_AUTH_USER と BASIC_AUTH_PASSWORD"
    end
  end

  test "Renderの動作確認用アドレスは認証なしで応答する" do
    with_env("BASIC_AUTH_USER" => "admin", "BASIC_AUTH_PASSWORD" => "secret") do
      get rails_health_check_path
      assert_response :success
    end
  end
end

# 4ステップ（① 依頼場所 → ② 問い合わせ内容 → ③ 希望内容 → ④ その他伝達事項）の画面
class RequestStepsTest < ActionDispatch::IntegrationTest
  test "入力画面に4つのステップが順番に並ぶ" do
    get new_inquiry_path
    assert_select "ol.stepper li", 4
    assert_select ".substep#step-1 h3", text: /修理の依頼場所/
    assert_select ".substep#step-2 h3", text: /問い合わせ内容/
    assert_select ".substep#step-3 h3", text: /お客様の希望内容/
    assert_select ".substep#step-4 h3", text: /その他伝達事項/
    assert_select ".substep#step-4 textarea[name='inquiry[detail]']"
    assert_select ".substep#step-4 input[type=file]"
    body = response.body
    positions = (1..4).map { |n| body.index("id=\"step-#{n}\"") }
    assert_equal positions.sort, positions
  end

  test "希望内容ごとの記入例を画面に渡している" do
    get new_inquiry_path
    examples = JSON.parse(css_select("textarea[name='inquiry[detail]']").first["data-examples"])
    assert_equal AppSettings::DETAIL_EXAMPLES, examples
  end

  test "希望内容を選ばずに送ると、選ぶよう案内する" do
    post inquiries_path, params: { inquiry: valid_params(request_type: "") }
    assert_response :unprocessable_entity
    assert_select ".alert-error", text: /③ お客様の希望内容を選んでください/
  end

  test "詳細画面・履歴・Slackに問い合わせ内容が出る" do
    stub_webhook_success
    post inquiries_path, params: { inquiry: valid_params(request_type: "クレーム・修理依頼", location_list: %w[玄関],
                                                         issue_list: %w[玄関の鍵が開かない], detail: "夜までに来てほしい") }
    follow_redirect!
    assert_select "dl.detail .badge-type", text: "クレーム・修理依頼"
    assert_select "dl.detail dd", text: "玄関"
    assert_select "dl.detail dd", text: "玄関の鍵が開かない"
    assert_select "dl.detail dd.pre", text: "夜までに来てほしい"
    text = sent_webhook_texts.first
    assert_includes text, "*問い合わせ内容*：玄関の鍵が開かない"
    assert_includes text, "*伝達事項*：\n夜までに来てほしい"

    get inquiries_path
    assert_select "td .badge-type", text: "クレーム・修理依頼"
    assert_select "td .small", text: "玄関｜玄関の鍵が開かない"
  end

  test "問い合わせ内容で「その他」を選んで伝達事項が空なら、書くよう案内する" do
    post inquiries_path, params: { inquiry: valid_params(issue_list: %w[その他], detail: "") }
    assert_response :unprocessable_entity
    assert_select ".alert-error", text: /② で「その他」を選んだときは、④ に内容を書いてください/
  end

  test "履歴を希望内容で絞り込める" do
    create_inquiry(customer_name: "見積の客", request_type: "見積もり依頼")
    create_inquiry(customer_name: "修理の客", request_type: "クレーム・修理依頼")
    get inquiries_path, params: { type: "見積もり依頼" }
    assert_includes response.body, "見積の客"
    refute_includes response.body, "修理の客"
    assert_select "select[name=type] option[selected]", text: "見積もり依頼"
  end

  test "決められていない希望内容で絞り込もうとしたら全件を出す" do
    create_inquiry(customer_name: "山田")
    get inquiries_path, params: { type: "<script>" }
    assert_includes response.body, "山田"
  end
end
