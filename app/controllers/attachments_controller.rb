class AttachmentsController < ApplicationController
  # 添付PDFをブラウザで開く（保存もできます）
  def show
    file = Attachment.find_by(id: params[:id])
    return render(plain: "見つかりませんでした", status: :not_found) unless file

    send_data file.data, filename: file.filename, type: "application/pdf", disposition: "inline"
  end
end
