# frozen_string_literal: true

class CreateTriggerCursors < ActiveRecord::Migration[8.1]
  def change
    create_table :trigger_cursors do |t|
      t.string :workflow_key, null: false
      t.string :trigger_key, null: false
      t.string :message_id, null: false

      t.index %i[workflow_key trigger_key], unique: true
    end
  end
end
