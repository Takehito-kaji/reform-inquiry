require "test_helper"

# 添付PDFのチェック
class AttachmentTest < ActiveSupport::TestCase
  def pdf(name, content = pdf_content)
    Attachment.from_upload(upload(name, content))
  end

  def errors_for(*files)
    inquiry = Inquiry.new(valid_params)
    files.each { |f| inquiry.attachments << f }
    inquiry.validate
    inquiry.errors.full_messages
  end

  test "ファイル名からフォルダ名を取り除く" do
    assert_equal "見積.pdf", Attachment.clean_filename("C:\\Users\\yamada\\Desktop\\見積.pdf")
    assert_equal "passwd.pdf", Attachment.clean_filename("../../etc/passwd.pdf")
  end

  test "ファイル名の制御文字を取り除く" do
    assert_equal "図面.pdf", Attachment.clean_filename("図\n面\r.pdf")
  end

  test "ファイル名がなければ添付とする" do
    assert_equal "添付.pdf", Attachment.clean_filename("")
    assert_equal "添付.pdf", Attachment.clean_filename(".pdf")
  end

  test "長すぎるファイル名は短くする" do
    name = Attachment.clean_filename("あ" * 300 + ".pdf")
    assert_operator name.length, :<=, 150
    assert name.end_with?(".pdf")
  end

  test "文字コード情報のない日本語ファイル名も読める" do
    assert_equal "見積依頼書.pdf", Attachment.clean_filename("見積依頼書.pdf".b)
  end

  test "アップロードされた中身と大きさを記録する" do
    file = pdf("見積.pdf", pdf_content("A"))
    assert_equal pdf_content("A"), file.data
    assert_equal pdf_content("A").bytesize, file.byte_size
  end

  test "正しいPDFならエラーなし" do
    assert_empty errors_for(pdf("見積.pdf"), pdf("図面.PDF"))
  end

  test "拡張子がPDFでなければエラー" do
    assert_equal ["「写真.jpg」はPDFファイルではありません"], errors_for(pdf("写真.jpg"))
  end

  test "名前だけPDFで中身が違えばエラー" do
    assert_equal ["「偽物.pdf」はPDFファイルではありません"], errors_for(pdf("偽物.pdf", "これはPDFではない"))
  end

  test "空のファイルはエラー" do
    assert_equal ["「空.pdf」は中身が空です"], errors_for(pdf("空.pdf", ""))
  end

  test "大きすぎるファイルはエラー" do
    with_setting(:MAX_PDF_SIZE_MB, 1) do
      big = pdf_content + ("0" * 1024 * 1024)
      assert_equal ["「大.pdf」は大きすぎます（1MBまで）"], errors_for(pdf("大.pdf", big))
    end
  end

  test "個数が多すぎればエラー" do
    files = Array.new(AppSettings::MAX_PDF_COUNT + 1) { |n| pdf("#{n}.pdf") }
    assert_equal ["添付できるPDFは#{AppSettings::MAX_PDF_COUNT}個までです"], errors_for(*files)
  end

  test "問い合わせと一緒に保存される" do
    inquiry = Inquiry.new(valid_params)
    inquiry.attachments << pdf("見積.pdf", pdf_content("中身"))
    assert inquiry.save
    assert_equal pdf_content("中身"), Attachment.find_by(inquiry: inquiry).data.b
  end

  test "一覧用の読み込みではPDFの中身を読まない" do
    inquiry = Inquiry.new(valid_params)
    inquiry.attachments << pdf("見積.pdf")
    inquiry.save!
    row = inquiry.attachments.without_data.first
    assert_equal "見積.pdf", row.filename
    refute row.has_attribute?(:data)
  end
end
