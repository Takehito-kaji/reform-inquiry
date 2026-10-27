Rails.application.routes.draw do
  root "inquiries#new"

  resources :inquiries, only: %i[index new create show] do
    post :resend, on: :member         # Slack にもう一度送る
  end
  resources :attachments, only: :show # 添付PDFを開く
  get "zipcode", to: "zipcodes#show"  # 郵便番号から住所を探す

  # Render が「アプリが動いているか」を確認するためのアドレス
  get "up" => "rails/health#show", as: :rails_health_check
end
