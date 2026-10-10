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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_120200) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "last_used_ip"
    t.string "prefix", null: false
    t.text "token"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["prefix"], name: "index_api_tokens_on_prefix"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id", unique: true
  end

  create_table "assets", force: :cascade do |t|
    t.string "alt"
    t.text "caption"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.float "focal_x", default: 0.5, null: false
    t.float "focal_y", default: 0.5, null: false
    t.string "folder", default: "/", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_assets_on_deleted_at"
    t.index ["folder"], name: "index_assets_on_folder"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_label", default: "", null: false
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "ip"
    t.json "metadata", default: {}, null: false
    t.bigint "target_id"
    t.string "target_label", default: "", null: false
    t.string "target_type"
    t.string "user_agent"
    t.index ["action", "created_at"], name: "index_audit_logs_on_action_and_created_at"
    t.index ["actor_type", "actor_id", "created_at"], name: "idx_audit_actor"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["target_type", "target_id", "created_at"], name: "idx_audit_target"
  end

  create_table "block_types", force: :cascade do |t|
    t.boolean "built_in", default: false, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.json "defaults", default: {}, null: false
    t.boolean "deprecated", default: false, null: false
    t.string "description"
    t.json "fields", default: [], null: false
    t.string "icon"
    t.string "label", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["category"], name: "index_block_types_on_category"
    t.index ["slug"], name: "index_block_types_on_slug", unique: true
  end

  create_table "bulk_uploads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "errors_log", default: [], null: false
    t.integer "failed", default: 0, null: false
    t.string "folder", default: "/", null: false
    t.integer "processed", default: 0, null: false
    t.integer "skipped", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.integer "succeeded", default: 0, null: false
    t.integer "total", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["status"], name: "index_bulk_uploads_on_status"
    t.index ["user_id"], name: "index_bulk_uploads_on_user_id"
  end

  create_table "collection_entries", force: :cascade do |t|
    t.json "blocks", default: [], null: false
    t.text "body_markdown", default: "", null: false
    t.integer "category_entry_id"
    t.integer "collection_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.json "frontmatter", default: {}, null: false
    t.string "locale", default: "en", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.json "seo", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.integer "translation_group_id"
    t.datetime "unpublish_at"
    t.datetime "updated_at", null: false
    t.index ["category_entry_id"], name: "index_collection_entries_on_category_entry_id"
    t.index ["collection_id", "slug"], name: "index_collection_entries_on_collection_id_and_slug", unique: true
    t.index ["collection_id"], name: "index_collection_entries_on_collection_id"
    t.index ["deleted_at"], name: "index_collection_entries_on_deleted_at"
    t.index ["publish_at"], name: "index_collection_entries_on_publish_at"
    t.index ["published_at"], name: "index_collection_entries_on_published_at"
    t.index ["status"], name: "index_collection_entries_on_status"
    t.index ["translation_group_id"], name: "index_collection_entries_on_translation_group_id"
    t.index ["unpublish_at"], name: "index_collection_entries_on_unpublish_at"
  end

  create_table "collection_entry_versions", force: :cascade do |t|
    t.integer "author_id"
    t.json "blocks", default: [], null: false
    t.text "body_markdown", default: "", null: false
    t.integer "collection_entry_id", null: false
    t.string "comment"
    t.datetime "created_at", null: false
    t.json "frontmatter", default: {}, null: false
    t.index ["author_id"], name: "index_collection_entry_versions_on_author_id"
    t.index ["collection_entry_id", "created_at"], name: "idx_on_collection_entry_id_created_at_4ebebe55a3"
    t.index ["collection_entry_id"], name: "index_collection_entry_versions_on_collection_entry_id"
  end

  create_table "collections", force: :cascade do |t|
    t.json "build_config", default: {}, null: false
    t.integer "categories_collection_id"
    t.datetime "created_at", null: false
    t.boolean "enable_blocks", default: false, null: false
    t.string "icon"
    t.string "name", null: false
    t.text "notification_emails"
    t.json "notification_events", default: [], null: false
    t.json "schema", default: {}, null: false
    t.string "slug", null: false
    t.integer "tags_collection_id"
    t.datetime "updated_at", null: false
    t.index ["categories_collection_id"], name: "index_collections_on_categories_collection_id"
    t.index ["slug"], name: "index_collections_on_slug", unique: true
    t.index ["tags_collection_id"], name: "index_collections_on_tags_collection_id"
  end

  create_table "content_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "owner_id", null: false
    t.string "owner_type", null: false
    t.integer "position"
    t.string "ref_id", null: false
    t.string "ref_type", null: false
    t.index ["owner_type", "owner_id", "kind"], name: "index_content_references_on_owner_type_and_owner_id_and_kind"
    t.index ["owner_type", "owner_id"], name: "index_content_references_on_owner"
    t.index ["ref_type", "ref_id"], name: "index_content_references_on_ref_type_and_ref_id"
  end

  create_table "device_authorizations", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "denied_at"
    t.string "device_code", null: false
    t.datetime "expires_at", null: false
    t.string "hostname"
    t.string "label"
    t.string "purpose", default: "user", null: false
    t.datetime "updated_at", null: false
    t.string "user_code", null: false
    t.integer "user_id"
    t.index ["device_code"], name: "index_device_authorizations_on_device_code", unique: true
    t.index ["user_code"], name: "index_device_authorizations_on_user_code", unique: true
    t.index ["user_id"], name: "index_device_authorizations_on_user_id"
  end

  create_table "form_emails", force: :cascade do |t|
    t.json "blocks", default: [], null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "form_id", null: false
    t.string "from_field"
    t.string "kind", null: false
    t.string "recipients"
    t.text "site_template"
    t.string "site_template_digest"
    t.datetime "site_template_received_at"
    t.string "subject", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["form_id", "kind"], name: "index_form_emails_on_form_id_and_kind", unique: true
    t.index ["form_id"], name: "index_form_emails_on_form_id"
  end

  create_table "form_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.integer "form_id", null: false
    t.string "ip"
    t.json "meta", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["form_id", "created_at"], name: "index_form_submissions_on_form_id_and_created_at"
    t.index ["form_id"], name: "index_form_submissions_on_form_id"
  end

  create_table "forms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.json "fields", default: [], null: false
    t.string "notify_webhook_url"
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "submit_label", default: "Submit", null: false
    t.string "submit_url"
    t.text "success_message"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.json "webhook_body", default: {}, null: false
    t.index ["deleted_at"], name: "index_forms_on_deleted_at"
    t.index ["slug"], name: "index_forms_on_slug", unique: true
  end

  create_table "globals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "icon"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.json "schema", default: {}, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["deleted_at"], name: "index_globals_on_deleted_at"
    t.index ["slug"], name: "index_globals_on_slug", unique: true
  end

  create_table "hello_greetings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_hello_greetings_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.text "billing_address"
    t.string "company"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "customer_email"
    t.string "customer_name", null: false
    t.string "customer_phone"
    t.date "due_on"
    t.date "issued_on"
    t.json "line_items", default: [], null: false
    t.text "notes"
    t.string "number", null: false
    t.datetime "paid_at"
    t.string "payment_link"
    t.integer "quote_request_id"
    t.datetime "sent_at"
    t.integer "shipping_cents", default: 0, null: false
    t.string "status", default: "draft", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.text "terms"
    t.string "token", null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["quote_request_id"], name: "index_invoices_on_quote_request_id"
    t.index ["status", "created_at"], name: "index_invoices_on_status_and_created_at"
    t.index ["token"], name: "index_invoices_on_token", unique: true
  end

  create_table "page_versions", force: :cascade do |t|
    t.integer "author_id"
    t.json "blocks", default: [], null: false
    t.string "comment"
    t.datetime "created_at", null: false
    t.integer "page_id", null: false
    t.index ["author_id"], name: "index_page_versions_on_author_id"
    t.index ["page_id", "created_at"], name: "index_page_versions_on_page_id_and_created_at"
    t.index ["page_id"], name: "index_page_versions_on_page_id"
  end

  create_table "pages", force: :cascade do |t|
    t.json "blocks", default: [], null: false
    t.integer "category_entry_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "depth", default: 0, null: false
    t.json "frontmatter", default: {}, null: false
    t.string "locale", default: "en", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "parent_id"
    t.string "path", null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.json "schema", default: {"fields" => []}, null: false
    t.json "seo", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.integer "translation_group_id"
    t.datetime "unpublish_at"
    t.datetime "updated_at", null: false
    t.index ["category_entry_id"], name: "index_pages_on_category_entry_id"
    t.index ["deleted_at"], name: "index_pages_on_deleted_at"
    t.index ["locale"], name: "index_pages_on_locale"
    t.index ["parent_id", "slug"], name: "index_pages_on_parent_id_and_slug", unique: true
    t.index ["parent_id"], name: "index_pages_on_parent_id"
    t.index ["path"], name: "index_pages_on_path", unique: true
    t.index ["publish_at"], name: "index_pages_on_publish_at"
    t.index ["published_at"], name: "index_pages_on_published_at"
    t.index ["status"], name: "index_pages_on_status"
    t.index ["translation_group_id"], name: "index_pages_on_translation_group_id"
    t.index ["unpublish_at"], name: "index_pages_on_unpublish_at"
  end

  create_table "plugin_changes", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.string "from_version"
    t.string "key"
    t.text "message"
    t.string "repo", null: false
    t.integer "requested_by_id"
    t.string "status", default: "running", null: false
    t.string "to_version"
    t.datetime "updated_at", null: false
    t.index ["requested_by_id"], name: "index_plugin_changes_on_requested_by_id"
    t.index ["status"], name: "index_plugin_changes_on_status"
  end

  create_table "quote_requests", force: :cascade do |t|
    t.string "company"
    t.datetime "created_at", null: false
    t.string "customer_email"
    t.string "customer_name", null: false
    t.string "customer_phone"
    t.string "ip"
    t.json "items", default: [], null: false
    t.text "message"
    t.json "meta", default: {}, null: false
    t.text "notes"
    t.string "page_url"
    t.string "source", default: "site", null: false
    t.string "status", default: "new", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_email"], name: "index_quote_requests_on_customer_email"
    t.index ["status", "created_at"], name: "index_quote_requests_on_status_and_created_at"
  end

  create_table "record_documents", force: :cascade do |t|
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.index ["record_type", "record_id"], name: "index_record_documents_on_record_type_and_record_id", unique: true
  end

  create_table "redirects", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "destination_url", null: false
    t.integer "hit_count", default: 0, null: false
    t.datetime "last_hit_at"
    t.text "notes"
    t.string "source_path", null: false
    t.integer "status_code", default: 301, null: false
    t.datetime "updated_at", null: false
    t.boolean "wildcard", default: false, null: false
    t.index ["active", "wildcard"], name: "index_redirects_on_active_and_wildcard"
    t.index ["source_path"], name: "index_redirects_on_source_path", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.json "permissions", default: [], null: false
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "service_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.datetime "last_used_at"
    t.string "last_used_ip"
    t.string "name", null: false
    t.string "prefix", null: false
    t.datetime "revoked_at"
    t.integer "role_id", null: false
    t.text "token"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_service_tokens_on_created_by_id"
    t.index ["revoked_at"], name: "index_service_tokens_on_revoked_at"
    t.index ["role_id"], name: "index_service_tokens_on_role_id"
    t.index ["token_digest"], name: "index_service_tokens_on_token_digest", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.string "key", null: false
    t.text "secrets"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "tag_entry_id", null: false
    t.integer "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_entry_id"], name: "index_taggings_on_tag_entry_id"
    t.index ["taggable_type", "taggable_id", "tag_entry_id"], name: "index_taggings_uniq", unique: true
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "translation_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
  end

  create_table "upgrades", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "external_url"
    t.datetime "finished_at"
    t.string "from_version", null: false
    t.text "message"
    t.integer "requested_by_id"
    t.string "status", default: "running", null: false
    t.string "to_version", null: false
    t.datetime "updated_at", null: false
    t.string "via", null: false
    t.index ["requested_by_id"], name: "index_upgrades_on_requested_by_id"
    t.index ["status"], name: "index_upgrades_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.json "recovery_code_digests", default: [], null: false
    t.integer "role_id"
    t.boolean "totp_enabled", default: false, null: false
    t.datetime "totp_enabled_at"
    t.string "totp_secret"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.string "event", null: false
    t.text "payload", null: false
    t.integer "response_status"
    t.boolean "success", default: false, null: false
    t.integer "webhook_id", null: false
    t.index ["event", "created_at"], name: "index_webhook_deliveries_on_event_and_created_at"
    t.index ["webhook_id", "created_at"], name: "index_webhook_deliveries_on_webhook_id_and_created_at"
    t.index ["webhook_id"], name: "index_webhook_deliveries_on_webhook_id"
  end

  create_table "webhooks", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.json "event_filters", default: {}, null: false
    t.json "events", default: [], null: false
    t.integer "failure_count", default: 0, null: false
    t.json "headers", default: {}, null: false
    t.datetime "last_delivery_at"
    t.string "last_status"
    t.string "name", null: false
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["active"], name: "index_webhooks_on_active"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "collection_entries", "collection_entries", column: "category_entry_id", on_delete: :nullify
  add_foreign_key "collection_entries", "collections"
  add_foreign_key "collection_entries", "translation_groups"
  add_foreign_key "collection_entry_versions", "collection_entries"
  add_foreign_key "collection_entry_versions", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "collections", "collections", column: "categories_collection_id", on_delete: :nullify
  add_foreign_key "collections", "collections", column: "tags_collection_id", on_delete: :nullify
  add_foreign_key "device_authorizations", "users", on_delete: :cascade
  add_foreign_key "form_emails", "forms", on_delete: :cascade
  add_foreign_key "form_submissions", "forms"
  add_foreign_key "hello_greetings", "users"
  add_foreign_key "invoices", "quote_requests"
  add_foreign_key "page_versions", "pages"
  add_foreign_key "page_versions", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "pages", "collection_entries", column: "category_entry_id", on_delete: :nullify
  add_foreign_key "pages", "pages", column: "parent_id"
  add_foreign_key "pages", "translation_groups"
  add_foreign_key "plugin_changes", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "collection_entries", column: "tag_entry_id", on_delete: :cascade
  add_foreign_key "upgrades", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "users", "roles"
  add_foreign_key "webhook_deliveries", "webhooks"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "record_documents_fts", "fts5", ["title", "body", "tokenize='trigram'"]
end
