require "net/http"

class ZipcodesController < ApplicationController
  # 郵便番号から住所を探す（無料の zipcloud API を使用）
  def show
    code = params[:code].to_s.tr("０-９", "0-9").delete("^0-9")
    return render(json: { error: "郵便番号は7桁で入力してください" }, status: :bad_request) unless code.length == 7

    res  = Net::HTTP.get_response(URI("https://zipcloud.ibsnet.co.jp/api/search?zipcode=#{code}"))
    data = JSON.parse(res.body)
    r    = data["results"]&.first
    return render(json: { error: "住所が見つかりませんでした" }, status: :not_found) unless r

    render json: { address: "#{r['address1']}#{r['address2']}#{r['address3']}" }
  rescue StandardError
    render json: { error: "住所検索に失敗しました。手入力してください" }, status: :bad_gateway
  end
end
