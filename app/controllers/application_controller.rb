class ApplicationController < ActionController::Base
  # インターネットに公開されるので、ID とパスワードを知っている人だけが開けるようにする（Basic認証）
  before_action :basic_auth

  private

  def basic_auth
    user = ENV["BASIC_AUTH_USER"].to_s
    pass = ENV["BASIC_AUTH_PASSWORD"].to_s

    if user.empty? || pass.empty?
      return unless Rails.env.production?

      # 本番で設定し忘れたまま公開しないよう、画面を開けなくする
      render plain: "BASIC_AUTH_USER と BASIC_AUTH_PASSWORD を Render の「Environment」に設定してください。" \
                    "（お客様の情報を守るため、設定するまで画面は開けません）",
             status: :service_unavailable
      return
    end

    authenticate_or_request_with_http_basic("Reform Inquiry") do |given_user, given_pass|
      ActiveSupport::SecurityUtils.secure_compare(given_user, user) &
        ActiveSupport::SecurityUtils.secure_compare(given_pass, pass)
    end
  end
end
