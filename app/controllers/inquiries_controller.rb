class InquiriesController < ApplicationController
  before_action :set_inquiry, only: %i[show resend]

  # 受付履歴
  def index
    @q    = params[:q].to_s.strip
    @type = AppSettings.request_types.include?(params[:type]) ? params[:type] : ""
    @inquiries  = Inquiry.search(@q).of_type(@type).order(id: :desc).limit(100)
    @pdf_counts = Attachment.where(inquiry_id: @inquiries.map(&:id)).group(:inquiry_id).count
  end

  # 入力画面
  def new
    @inquiry = Inquiry.new(
      received_by:  cookies[:received_by],
      urgency:      AppSettings::URGENCY.first,
      contact_time: AppSettings::CONTACT_TIMES.first,
      sales_person: AppSettings.sales_people.first
    )
  end

  # 保存して Slack に送る
  def create
    @inquiry = Inquiry.new(inquiry_params)
    files = uploaded_files
    files.each { |file| @inquiry.attachments << Attachment.from_upload(file) }

    if @inquiry.save
      # 受付者名を次回も自動で選んでおく
      cookies.permanent[:received_by] = @inquiry.received_by
      SlackNotifier.new(@inquiry).deliver
      redirect_to inquiry_path(@inquiry, from: "new")
    else
      # ブラウザの仕組み上、選んだファイルは画面に残せないため選び直してもらう
      @reselect_pdf = files.any?
      render :new, status: :unprocessable_entity
    end
  end

  # 詳細
  def show
    @from_new    = params[:from] == "new"
    @attachments = @inquiry.attachments.without_data
  end

  # Slack にもう一度送る
  def resend
    SlackNotifier.new(@inquiry).deliver
    redirect_to inquiry_path(@inquiry)
  end

  private

  def set_inquiry
    @inquiry = Inquiry.find_by(id: params[:id])
    render plain: "見つかりませんでした", status: :not_found unless @inquiry
  end

  def inquiry_params
    params.require(:inquiry).permit(
      :received_by, :customer_name, :customer_kana, :phone, :postal_code, :address,
      :detail, :urgency, :contact_time, :sales_person, :request_type, location_list: [], issue_list: []
    )
  end

  # フォームから送られたファイルだけを取り出す（何も選ばれていない欄は無視）
  def uploaded_files
    Array(params.dig(:inquiry, :attachments)).select do |file|
      file.respond_to?(:original_filename) && file.original_filename.present?
    end
  end
end
