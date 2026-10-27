# 入力画面を ①依頼場所 → ②問い合わせ内容 → ③希望内容 → ④その他伝達事項 の4ステップにしたときの変更
class AddIssuesToInquiries < ActiveRecord::Migration[8.0]
  def change
    # ② よくある問い合わせ内容（「お風呂が水漏れしている」など。「、」区切り）
    add_column :inquiries, :issues, :text
  end
end
