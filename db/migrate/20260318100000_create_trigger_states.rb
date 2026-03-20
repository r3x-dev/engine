class CreateTriggerStates < ActiveRecord::Migration[8.1]
  def change
    create_table :trigger_states do |t|
      t.string :workflow_key, null: false
      t.string :trigger_key, null: false
      t.string :trigger_type, null: false
      t.json :state, null: false, default: {}
      t.datetime :last_checked_at
      t.datetime :last_triggered_at
      t.datetime :last_error_at
      t.text :last_error_message

      t.timestamps
    end

    add_index :trigger_states, [ :workflow_key, :trigger_key ], unique: true
    add_index :trigger_states, :workflow_key
    add_index :trigger_states, :trigger_type
  end
end
