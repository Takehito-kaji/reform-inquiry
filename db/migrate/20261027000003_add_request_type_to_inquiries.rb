# 入力画面を ①依頼場所 → ②希望内容 → ③詳細 の3ステップにしたときの変更
class AddRequestTypeToInquiries < ActiveRecord::Migration[8.0]
  def change
    # ② お客様の希望内容（リフォーム依頼・クレーム・修理依頼・見積もり依頼・その他）
    add_column :inquiries, :request_type, :string, limit: 30
    add_index  :inquiries, :request_type

    # ① 今まで「修理内容」として保存していた列を「依頼場所」として使う
    rename_column :inquiries, :repair_items, :locations
  end
end
