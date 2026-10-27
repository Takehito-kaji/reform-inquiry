require "test_helper"

# Slack に送る文章づくりのテスト
class SlackMessageTest < ActiveSupport::TestCase
  IDS = { "山田" => "U012AB3CD", "佐藤" => "", "鈴木" => "@u0456efgh", "田中" => "山田さん" }.freeze

  def mention(sales, urgency = "通常")
    with_setting(:SALES_SLACK_IDS, IDS) { SlackMessage.mention_for(sales, urgency) }
  end

  def inquiry(attrs = {})
    create_inquiry({
      customer_kana: "ヤマモト ハナコ", postal_code: "460-0001", repair_item_list: %w[トイレ 水漏れ],
      detail: "床が濡れている", contact_time: "午前中", created_at: Time.zone.local(2026, 10, 13, 9, 5)
    }.merge(attrs))
  end

  def text(i = inquiry, **opts)
    SlackMessage.new(i, **opts).to_s
  end

  test "IDが登録された営業にはメンションを付ける" do
    assert_equal "<@U012AB3CD>", mention("山田")
  end

  test "IDが空欄の営業にはメンションを付けない" do
    assert_equal "", mention("佐藤")
  end

  test "IDにアットマークや小文字が混ざっていても正しく扱う" do
    assert_equal "<@U0456EFGH>", mention("鈴木")
  end

  test "IDの形式が違えばメンションしない" do
    assert_equal "", mention("田中")
  end

  test "未定のときは初期設定ではメンションしない" do
    assert_equal "", mention("未定")
  end

  test "未定のとき全員通知の設定なら全員にメンション" do
    with_setting(:MENTION_ALL_WHEN_UNASSIGNED, true) { assert_equal "<!channel>", mention("未定") }
  end

  test "急ぎのとき全員通知の設定なら担当と全員にメンション" do
    with_setting(:MENTION_ALL_WHEN_URGENT, true) do
      assert_equal "<@U012AB3CD> <!channel>", mention("山田", "急ぎ")
      assert_equal "<@U012AB3CD>", mention("山田", "通常")
    end
  end

  test "お客様情報と依頼内容がすべて入る" do
    i = inquiry
    t = text(i)
    [
      "新規リフォーム問い合わせ No.#{i.id}", "担当営業：山田", "山本 花子 様（ヤマモト ハナコ）",
      "090-1234-5678", "〒460-0001 愛知県名古屋市中区三の丸1-1", "連絡希望*：午前中",
      "トイレ、水漏れ", "床が濡れている", "受付：事務A　10/13 09:05"
    ].each { |part| assert_includes t, part }
  end

  test "住所のGoogleマップリンクが付く" do
    assert_match %r{<https://www\.google\.com/maps/search/\?api=1&query=[^|]+\|地図を開く>}, text
  end

  test "通常は電話マーク、急ぎは目立つ見出し" do
    assert_includes text, "📞"
    assert_includes text(inquiry(urgency: "至急（当日中）")), "🚨【至急（当日中）】"
  end

  test "メンションは1行目に入る" do
    with_setting(:SALES_SLACK_IDS, { "山田" => "U012AB3CD" }) do
      assert_equal "<@U012AB3CD>", text.lines.first.chomp
    end
  end

  test "空の項目は表示しない" do
    t = text(inquiry(customer_kana: "", postal_code: "", contact_time: "", detail: ""))
    refute_includes t, "（）"
    refute_includes t, "〒"
    refute_includes t, "連絡希望"
    refute_includes t, "*詳細*"
  end

  test "修理内容が空ならメモ参照と表示" do
    assert_includes text(inquiry(repair_item_list: [])), "（詳細メモ参照）"
  end

  test "メモに全員通知の書式を書かれても通知は飛ばない" do
    t = text(inquiry(detail: "<!channel> 至急！ <@U999999999>"))
    refute_includes t, "<!channel>"
    refute_includes t, "<@U999999999>"
    assert_includes t, "&lt;!channel&gt; 至急！"
  end

  test "記号を含む名前や住所も読める形で送る" do
    t = text(inquiry(customer_name: "A&B商事", address: "名古屋市<1-2>"))
    assert_includes t, "A&amp;B商事"
    assert_includes t, "名古屋市&lt;1-2&gt;"
  end

  test "アプリのアドレスがあれば受付アプリへのリンクを付ける" do
    i = inquiry
    assert_includes text(i, base_url: "https://reform.onrender.com/"),
                    "<https://reform.onrender.com/inquiries/#{i.id}|受付アプリで開く>"
    refute_includes text(i), "受付アプリで開く"
  end

  test "添付PDFのファイル名を載せる" do
    i = inquiry
    i.attachments.create!(filename: "見積依頼書.pdf", data: pdf_content, byte_size: 10)
    i.attachments.create!(filename: "<!channel>.pdf", data: pdf_content, byte_size: 10)

    assert_includes text(i), "*添付PDF*（2件）：見積依頼書.pdf、&lt;!channel&gt;.pdf（受付アプリで見られます）"
    assert_includes text(i, pdf_in_thread: true), "（このメッセージのスレッドに添付しています）"
  end
end
