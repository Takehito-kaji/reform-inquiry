require "test_helper"

# 問い合わせの入力値の整形とチェック
class InquiryTest < ActiveSupport::TestCase
  def build(overrides = {})
    Inquiry.new(valid_params(overrides))
  end

  def errors_for(overrides)
    inquiry = build(overrides)
    inquiry.validate
    inquiry.errors.full_messages
  end

  test "全角の数字とハイフンを半角にそろえる" do
    i = build(phone: "０９０－１２３４－５６７８", postal_code: "４６０ー０００１")
    assert_equal "090-1234-5678", i.phone
    assert_equal "460-0001", i.postal_code
  end

  test "前後の空白（全角スペースも）を取り除く" do
    i = build(customer_name: "  山本 花子　", address: " 名古屋市 ")
    assert_equal "山本 花子", i.customer_name
    assert_equal "名古屋市", i.address
  end

  test "選択肢にない依頼場所は捨てる" do
    assert_equal %w[トイレ], build(location_list: %w[トイレ 存在しない場所 <script>]).location_list
  end

  test "依頼場所は「、」区切りで保存する" do
    assert_equal "トイレ、洗面所", build.locations
  end

  test "希望内容を選んでいなければエラー" do
    assert_includes errors_for(request_type: ""), "③ お客様の希望内容を選んでください"
  end

  test "希望内容は決められた4種類だけ" do
    AppSettings.request_types.each { |type| assert_empty errors_for(request_type: type) }
    assert_includes errors_for(request_type: "なんでも"), "③ お客様の希望内容を選んでください"
  end

  test "希望内容で絞り込める" do
    create_inquiry(customer_name: "見積の客", request_type: "見積もり依頼")
    create_inquiry(customer_name: "修理の客", request_type: "クレーム・修理依頼")
    assert_equal ["見積の客"], Inquiry.of_type("見積もり依頼").map(&:customer_name)
    assert_equal 2, Inquiry.of_type("").count
  end

  test "3ステップにする前の受付は希望内容を未設定と表示する" do
    i = create_inquiry
    i.update_column(:request_type, nil)
    assert_equal "未設定", i.reload.request_type_label
  end

  test "3ステップにする前の受付も、そのまま保存し直せる" do
    i = create_inquiry
    i.update_column(:request_type, nil)
    assert i.reload.update(detail: "あとから追記")
  end

  test "緊急度が不正な値なら通常にする" do
    i = build(urgency: "超特急")
    i.validate
    assert_equal "通常", i.urgency
    assert i.valid?
  end

  test "正しい入力ならエラーなし" do
    assert_empty errors_for({})
  end

  test "氏名が空ならエラー" do
    assert_includes errors_for(customer_name: ""), "お客様の氏名を入力してください"
  end

  test "全角スペースだけの氏名は未入力として扱う" do
    assert_includes errors_for(customer_name: "　　"), "お客様の氏名を入力してください"
  end

  test "住所が空ならエラー" do
    assert_includes errors_for(address: " "), "住所を入力してください"
  end

  test "電話番号が空ならエラー" do
    assert_includes errors_for(phone: ""), "電話番号を入力してください"
  end

  test "電話番号の桁数が足りなければエラー" do
    assert_includes errors_for(phone: "052-123"), "電話番号の桁数を確認してください（10〜11桁）"
  end

  test "電話番号はハイフンなし10桁や11桁でもOK" do
    assert_empty errors_for(phone: "0521234567")
    assert_empty errors_for(phone: "09012345678")
  end

  test "依頼場所も問い合わせ内容も伝達事項も空ならエラー" do
    assert_includes errors_for(location_list: [], issue_list: [], detail: ""),
                    "① 依頼場所か ② 問い合わせ内容を選ぶか、④ に内容を書いてください"
  end

  test "どれか1つでも入っていればOK" do
    assert_empty errors_for(location_list: [], issue_list: [], detail: "雨戸が閉まらない")
    assert_empty errors_for(location_list: [], issue_list: %w[雨漏りしている], detail: "")
    assert_empty errors_for(location_list: %w[屋根], issue_list: [], detail: "")
  end

  test "問い合わせ内容は「、」区切りで保存し、選択肢にないものは捨てる" do
    i = build(issue_list: ["お風呂が水漏れしている", "存在しない内容", "玄関の鍵が開かない"])
    assert_equal "お風呂が水漏れしている、玄関の鍵が開かない", i.issues
    assert_equal ["お風呂が水漏れしている", "玄関の鍵が開かない"], i.issue_list
  end

  test "問い合わせ内容で「その他」を選んだら伝達事項が必要" do
    assert_includes errors_for(issue_list: %w[その他], detail: ""), "② で「その他」を選んだときは、④ に内容を書いてください"
    assert_empty errors_for(issue_list: %w[その他], detail: "網戸が外れた")
  end

  test "問い合わせ内容でも検索できる" do
    create_inquiry(customer_name: "鍵の客", issue_list: %w[玄関の鍵が開かない])
    create_inquiry(customer_name: "雨の客", issue_list: %w[雨漏りしている])
    assert_equal ["鍵の客"], Inquiry.search("鍵が開かない").map(&:customer_name)
  end

  test "よくある問い合わせ内容は10個とその他" do
    assert_equal 11, AppSettings.all_issues.size
    assert_equal "その他", AppSettings.all_issues.last
    linked = AppSettings::COMMON_ISSUES.values.flatten.uniq
    assert_empty linked - AppSettings.all_locations, "関係する場所は ① の選択肢から選ぶ"
  end

  test "複数のエラーをまとめて返す" do
    assert_equal 4, errors_for(customer_name: "", address: "", phone: "", request_type: "").size
  end

  test "氏名・電話番号・住所で検索できる" do
    create_inquiry(customer_name: "伊藤 次郎", phone: "052-111-2222", address: "名古屋市千種区")
    create_inquiry(customer_name: "加藤 三郎", phone: "0561-33-4444", address: "瀬戸市")

    assert_equal ["伊藤 次郎"], Inquiry.search("伊藤").map(&:customer_name)
    assert_equal ["加藤 三郎"], Inquiry.search("0561").map(&:customer_name)
    assert_equal ["伊藤 次郎"], Inquiry.search("千種").map(&:customer_name)
    assert_equal 2, Inquiry.search("").count
  end

  test "検索語の % や _ はそのままの文字として探す" do
    create_inquiry(customer_name: "山田")
    assert_empty Inquiry.search("%")
    assert_empty Inquiry.search("_")
  end

  test "地図のリンクを作る" do
    assert_equal "https://www.google.com/maps/search/?api=1&query=%E5%90%8D%E5%8F%A4%E5%B1%8B%20%E4%B8%AD%E5%8C%BA",
                 build(address: "名古屋 中区").map_url
  end
end
