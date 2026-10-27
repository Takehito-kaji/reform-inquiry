# 添付PDF。Render の無料プランでは保存したファイルが再起動で消えるため、
# PDF の中身もデータベースに保存します
class CreateAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :attachments do |t|
      t.references :inquiry,  null: false, foreign_key: true
      t.string     :filename, null: false                      # 元のファイル名
      t.integer    :byte_size, null: false                     # 大きさ（バイト）
      t.binary     :data,      null: false, limit: 16.megabytes # PDF の中身

      t.timestamps
    end
  end
end
