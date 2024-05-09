require 'pry'

class ClientDatabaseSwitcher
  def initialize(app)
    @app = app
    @client_connections = {}
  end

  def call(env)
    begin
      Rails.logger.info "Trying to fetch client...."

      ActiveRecord::Base.transaction do
        # WE NEED TO SWITCH LOCAL DATABASE JUST TO FETCH CLIENTS FROM OUR OWN DATABASE.
        switch_to_local_database_connection do
          # Identify the client context based on domain or other criteria
          @client = Client.find_by(domain: env['HTTP_HOST'])
        end

        # THROW AN ERROR IF CLIENT NOT FOUND.
        return [404, { 'Content-Type' => 'text/plain' }, ['Domain not found']] unless @client

        # CONTINUE THE FLOW IF CLIENT DOES NOT HAVE OWN DATABASE.
        return @app.call(env) if @client.has_own_database == false


        Rails.logger.info "Client has been fecthed successfully, Starting to establish database connection...."
        # Get or set the database connection for the client
        database_connection = get_or_set_database_connection(@client)

        # Set the database connection for the current request
        set_database_connection(database_connection)

        Rails.logger.info "Connection has been established successfully, running pending migrations now..."

        # Run pending migrations
        run_pending_migrations(@client)

        Rails.logger.info "Success."
      end

      # Call the next middleware or application
      @app.call(env)
    rescue ActiveRecord::ConnectionNotEstablished => e
      # Log the error
      Rails.logger.error "Failed to establish database connection: #{e.message}"

      # Render an error response
      [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
    rescue StandardError => e
      # Log the error
      Rails.logger.error "An unexpected error occurred: #{e.message}"

      # Render an error response
      [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
    ensure
      # Reset the database connection after each request
      ActiveRecord::Base.connection_handler.clear_active_connections!
    end
  end

  private

  def get_or_set_database_connection(client)
    return nil unless client

    @client_connections[client.id] ||= establish_database_connection(client)
  end

  def establish_database_connection(client)
    ActiveRecord::Base.establish_connection(client.database_url)
    ActiveRecord::Base.connection_pool.checkout
  end

  def set_database_connection(database_connection)
    return unless database_connection

    ActiveRecord::Base.connection_handler.clear_active_connections!
    ActiveRecord::Base.connection_handler.establish_connection(database_connection.instance_variable_get(:@config))
  end

  # def empty_database?(database_connection)
  #   database_connection.tables.empty?
  # end

  def run_pending_migrations(client)
    return unless client

    # Run migrations if the client's database is empty
    ActiveRecord::MigrationContext.new(Rails.root.join('db', 'migrate'), ActiveRecord::SchemaMigration).migrate
  end

  def switch_to_local_database_connection
    # Store current connection specification
    previous_connection_spec = ActiveRecord::Base.remove_connection if ActiveRecord::Base.connection_handler.active_connections?

    begin
      # Establish connection to the local database
      ActiveRecord::Base.establish_connection(:development)
      ActiveRecord::Base.connection_pool.with_connection { yield }
    ensure
      # Revert back to the previous connection
      ActiveRecord::Base.establish_connection(previous_connection_spec)
    end
  end
end

# TODO: To test with 2 different database url (Concurrency Issue Verification)
