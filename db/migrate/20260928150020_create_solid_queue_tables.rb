# db/migrate/<timestamp>_create_solid_queue_tables.rb
#
# Solid Queue ships its tables as db/queue_schema.rb, intended for a separate
# database. HAMS runs on a single Heroku Postgres, so load that schema into
# the primary connection once here instead.
class CreateSolidQueueTables < ActiveRecord::Migration[8.0]
  TABLES = %w[
    solid_queue_semaphores solid_queue_scheduled_executions solid_queue_recurring_tasks
    solid_queue_recurring_executions solid_queue_ready_executions solid_queue_processes
    solid_queue_pauses solid_queue_failed_executions solid_queue_claimed_executions
    solid_queue_blocked_executions solid_queue_jobs
  ].freeze

  def up
    load Rails.root.join("db/queue_schema.rb")
  end

  def down
    TABLES.each { |t| drop_table t, if_exists: true }
  end
end
