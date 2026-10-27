class CreateInquiries < ActiveRecord::Migration[8.0]
  def change
    create_table :inquiries do |t|
      t.string   :received_by,   limit: 50                  # 電話を受けた事務員
      t.string   :customer_name, limit: 100, null: false    # お客様氏名
      t.string   :customer_kana, limit: 100                 # フリガナ
      t.string   :phone,         limit: 20,  null: false    # 電話番号
      t.string   :postal_code,   limit: 10                  # 郵便番号
      t.string   :address,       null: false                # 住所
      t.text     :repair_items,  null: false                # 選んだ修理内容（「、」区切り）
      t.text     :detail                                    # 詳細メモ
      t.string   :urgency,       limit: 20,  null: false, default: "通常"
      t.string   :contact_time,  limit: 50                  # 連絡希望の時間帯
      t.string   :sales_person,  limit: 50                  # 担当営業
      t.boolean  :chat_sent,     null: false, default: false # Slack に送れたか
      t.datetime :chat_sent_at
      t.text     :chat_error                                # 送れなかったときの理由

      t.timestamps
    end
    add_index :inquiries, :created_at
  end
end
