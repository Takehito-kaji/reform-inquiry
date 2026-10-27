# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_10_27_000002) do
  create_table "attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "inquiry_id", null: false
    t.string "filename", null: false
    t.integer "byte_size", null: false
    t.binary "data", size: :long, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inquiry_id"], name: "index_attachments_on_inquiry_id"
  end

  create_table "inquiries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "received_by", limit: 50
    t.string "customer_name", limit: 100, null: false
    t.string "customer_kana", limit: 100
    t.string "phone", limit: 20, null: false
    t.string "postal_code", limit: 10
    t.string "address", null: false
    t.text "repair_items", null: false
    t.text "detail"
    t.string "urgency", limit: 20, default: "通常", null: false
    t.string "contact_time", limit: 50
    t.string "sales_person", limit: 50
    t.boolean "chat_sent", default: false, null: false
    t.datetime "chat_sent_at"
    t.text "chat_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_inquiries_on_created_at"
  end

  add_foreign_key "attachments", "inquiries"
end
