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
  # 3ステップにする前に受け付けた分（希望内容なし）はそのまま残せるよう、新しく受け付けるときだけ確認する
  validates :request_type,  inclusion: { in: ->(_) { AppSettings.request_types },
                                         message: "③ お客様の希望内容を選んでください" }, on: :create
  validate  :check_phone
  validate  :check_request
  validate  :check_other_issue
  validate  :check_attachments

  # 氏名・電話番号・住所のどれかに含まれる問い合わせを探す
  scope :search, ->(word) {
    next all if word.blank?

    like = "%#{sanitize_sql_like(word)}%"
    where("customer_name LIKE :q OR phone LIKE :q OR address LIKE :q OR issues LIKE :q", q: like)
  }

  # 希望内容で絞り込む（空なら全部）
  scope :of_type, ->(type) { type.present? ? where(request_type: type) : all }

  # ① 依頼場所は「、」区切りの文字で保存し、画面ではチェックボックスの配列として扱う
  def location_list
    locations.to_s.split("、")
  end

  def location_list=(list)
    self.locations = (Array(list).map(&:to_s) & AppSettings.all_locations).join("、")
  end

  # ② 問い合わせ内容も同じく「、」区切りで保存する
  def issue_list
    issues.to_s.split("、")
  end

  def issue_list=(list)
    self.issues = (Array(list).map(&:to_s) & AppSettings.all_issues).join("、")
  end

  # 画面や Slack に出す希望内容（3ステップにする前の受付は「未設定」）
  def request_type_label
    request_type.presence || "未設定"
  end

  def urgent?
    urgency != AppSettings::URGENCY.first
  end

  def map_url
    "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(address)}"
  end

  private

  def fix_choices
    self.locations ||= ""
    self.issues    ||= ""
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
    return if locations.present? || issues.present? || detail.present?

    errors.add(:base, "① 依頼場所か ② 問い合わせ内容を選ぶか、④ に内容を書いてください")
  end

  # ② で「その他」を選んだときは、何があったのかを ④ に書いてもらう
  def check_other_issue
    return unless issue_list.include?("その他") && detail.blank?

    errors.add(:base, "② で「その他」を選んだときは、④ に内容を書いてください")
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
