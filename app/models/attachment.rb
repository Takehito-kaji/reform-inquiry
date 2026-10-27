# 問い合わせに添付された PDF（中身もデータベースに保存します）
class Attachment < ApplicationRecord
  PDF_SIGNATURE = "%PDF-".b

  belongs_to :inquiry

  validate :check_pdf

  # 一覧などで PDF の中身まで読み込まないようにする
  scope :without_data, -> { select(column_names - ["data"]) }

  # フォームから送られてきたファイルから作る
  def self.from_upload(file)
    data = file.read.to_s.b
    new(filename: clean_filename(file.original_filename), data: data, byte_size: data.bytesize)
  end

  # ファイル名から、フォルダ名や制御文字など余計なものを取り除く
  def self.clean_filename(name)
    text = name.to_s.dup.force_encoding(Encoding::UTF_8).scrub("_")
    base = File.basename(text.tr("\\", "/")).gsub(/[[:cntrl:]]/, "").strip
    base = "添付.pdf" if base.empty? || base.start_with?(".")
    base.length > 150 ? "#{base[0, 146]}.pdf" : base
  end

  private

  def check_pdf
    if byte_size.to_i.zero?
      errors.add(:base, "「#{filename}」は中身が空です")
    elsif !filename.to_s.downcase.end_with?(".pdf") || !data.to_s.b.start_with?(PDF_SIGNATURE)
      errors.add(:base, "「#{filename}」はPDFファイルではありません")
    elsif byte_size > AppSettings::MAX_PDF_SIZE_MB * 1024 * 1024
      errors.add(:base, "「#{filename}」は大きすぎます（#{AppSettings::MAX_PDF_SIZE_MB}MBまで）")
    end
  end
end
