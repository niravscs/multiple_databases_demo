class CreateClients < ActiveRecord::Migration[7.1]
  def change
    create_table :clients do |t|
      t.string :domain
      t.string :unique_name
      t.boolean :has_own_database, default: false
      t.string :database_url, default: ""
      t.timestamps
    end
  end
end
