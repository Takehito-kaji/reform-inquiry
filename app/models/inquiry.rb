# 電話で受けた問い合わせ 1 件分
class Inquiry < ApplicationRecord
  has_many :attachments, -> { order(:id) }, dependent: :destroy, inverse_of: :inquiry, validate: false

  # 前後の空白（全角スペースも）を取り除く
  def self.trim(value)
    value.to_s.gsub(/\A[[:space:]　]+|[[:space:]　]+\z/, "")
  end

  # 全角の数字・ハイフンを半角にそろえる
  def self.to_hankaku(value)
    trim(value.to_s.tr("０-９－ー―", "0-9---"))
  end

  normalizes :received_by, :customer_name, :customer_kana, :address, :detail, with: ->(v) { Inquiry.trim(v) }
  normalizes :phone, :postal_code, with: ->(v) { Inquiry.to_hankaku(v) }

  before_validation :fix_choices

  validates :customer_name, presence: { message: "お客様の氏名を入力してください" }
  validates :address,       presence: { message: "住所を入力してください" }
  validate  :check_phone
  validate  :check_request
  validate  :check_attachments

  # 氏名・電話番号・住所のどれかに含まれる問い合わせを探す
  scope :search, ->(word) {
    next all if word.blank?

    like = "%#{sanitize_sql_like(word)}%"
    where("customer_name LIKE :q OR phone LIKE :q OR address LIKE :q", q: like)
  }

  # 修理内容は「、」区切りの文字で保存し、画面ではチェックボックスの配列として扱う
  def repair_item_list
    repair_items.to_s.split("、")
  end

  def repair_item_list=(list)
    self.repair_items = (Array(list).map(&:to_s) & AppSettings.all_repair_items).join("、")
  end

  def urgent?
    urgency != AppSettings::URGENCY.first
  end

  def map_url
    "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(address)}"
  end

  private

  def fix_choices
    self.repair_items ||= ""
    self.urgency = AppSettings::URGENCY.first unless AppSettings::URGENCY.include?(urgency)
  end

  def check_phone
    digits = phone.to_s.delete("^0-9")
    if digits.empty?
      errors.add(:phone, "電話番号を入力してください")
    elsif !(10..11).cover?(digits.length)
      errors.add(:phone, "電話番号の桁数を確認してください（10〜11桁）")
    end
  end

  def check_request
    return if repair_items.present? || detail.present?

    errors.add(:base, "修理内容を1つ以上選ぶか、詳細メモを入力してください")
  end

  def check_attachments
    if attachments.size > AppSettings::MAX_PDF_COUNT
      errors.add(:base, "添付できるPDFは#{AppSettings::MAX_PDF_COUNT}個までです")
      return
    end
    attachments.select(&:new_record?).each do |file|
      file.validate
      file.errors.full_messages.each { |message| errors.add(:base, message) }
    end
  end
end
