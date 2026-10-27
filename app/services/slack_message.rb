# Slack に投稿する文章を作る
class SlackMessage
  # 担当営業へのメンション（Slack の書式： <@メンバーID>、全員は <!channel>）
  def self.mention_for(sales, urgency)
    slack_id = AppSettings::SALES_SLACK_IDS[sales].to_s.strip.delete_prefix("@").upcase
    parts = []
    parts << "<@#{slack_id}>" if slack_id.match?(/\A[UW][A-Z0-9]{6,}\z/)

    urgent = urgency != AppSettings::URGENCY.first
    if (sales == "未定" && AppSettings::MENTION_ALL_WHEN_UNASSIGNED) || (urgent && AppSettings::MENTION_ALL_WHEN_URGENT)
      parts << "<!channel>"
    end
    parts.uniq.join(" ")
  end

  # 入力された文字を Slack に安全に載せる
  # （メモに「<!channel>」などと書かれても、全員通知が勝手に飛ばないようにする）
  def self.escape(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  # base_url: 受付アプリのアドレス（Slack に「受付アプリで開く」リンクを付ける）
  # pdf_in_thread: PDF をこのメッセージのスレッドに添付するかどうか
  def initialize(inquiry, base_url: nil, pdf_in_thread: false)
    @inquiry       = inquiry
    @base_url      = base_url.to_s.chomp("/")
    @pdf_in_thread = pdf_in_thread
  end

  def to_s
    i     = @inquiry
    e     = ->(value) { self.class.escape(value) }
    sales = i.sales_person.presence || "未定"
    head  = i.urgent? ? "🚨【#{e.(i.urgency)}】" : "📞"
    kana  = i.customer_kana.present? ? "（#{e.(i.customer_kana)}）" : ""
    zip   = i.postal_code.present? ? "〒#{e.(i.postal_code)} " : ""
    mention = self.class.mention_for(sales, i.urgency)

    lines = []
    lines << mention if mention.present?
    lines << "#{head} *新規リフォーム問い合わせ No.#{i.id}*"
    lines << "担当営業：#{e.(sales)}"
    lines << ""
    lines << "*お客様*：#{e.(i.customer_name)} 様#{kana}"
    lines << "*電話*：#{e.(i.phone)}"
    lines << "*住所*：#{zip}#{e.(i.address)}  <#{i.map_url}|地図を開く>"
    lines << "*連絡希望*：#{e.(i.contact_time)}" if i.contact_time.present?
    lines << ""
    lines << "*依頼内容*：#{i.repair_items.present? ? e.(i.repair_items) : '（詳細メモ参照）'}"
    lines << "*詳細*：\n#{e.(i.detail)}" if i.detail.present?
    lines << attachment_line if attachment_names.any?
    lines << "<#{@base_url}/inquiries/#{i.id}|受付アプリで開く>" if @base_url.present? && attachment_names.empty?
    lines << ""
    lines << "受付：#{e.(i.received_by)}　#{i.created_at&.in_time_zone&.strftime('%m/%d %H:%M')}"
    lines.join("\n")
  end

  private

  def attachment_names
    @attachment_names ||= @inquiry.attachments.without_data.map(&:filename)
  end

  def attachment_line
    names = attachment_names.map { |n| self.class.escape(n) }.join("、")
    where =
      if @pdf_in_thread then "（このメッセージのスレッドに添付しています）"
      elsif @base_url.present? then "  <#{@base_url}/inquiries/#{@inquiry.id}|受付アプリで開く>"
      else "（受付アプリで見られます）"
      end
    "*添付PDF*（#{attachment_names.size}件）：#{names}#{where}"
  end
end
