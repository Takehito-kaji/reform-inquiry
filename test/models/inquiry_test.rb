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

  test "選択肢にない修理内容は捨てる" do
    assert_equal %w[トイレ], build(repair_item_list: %w[トイレ 存在しない項目 <script>]).repair_item_list
  end

  test "修理内容は「、」区切りで保存する" do
    assert_equal "トイレ、水漏れ", build.repair_items
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

  test "修理内容もメモも空ならエラー" do
    assert_includes errors_for(repair_item_list: [], detail: ""), "修理内容を1つ以上選ぶか、詳細メモを入力してください"
  end

  test "修理内容が未選択でもメモがあればOK" do
    assert_empty errors_for(repair_item_list: [], detail: "雨戸が閉まらない")
  end

  test "複数のエラーをまとめて返す" do
    assert_equal 3, errors_for(customer_name: "", address: "", phone: "").size
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
