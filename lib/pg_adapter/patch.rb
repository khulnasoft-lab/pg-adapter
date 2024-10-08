# frozen_string_literal: true
require "active_record/connection_adapters/postgresql_adapter"

module PgAdapter
  module Patch
    CONNECTION_ERROR = [
      "Lost connection",
      "gone away",
      "read-only",
      "PG::ReadOnlySqlTransaction",
      "PG::UnableToSend",
      "PG::ConnectionBad",
      "the database system is starting up",
      "connection is closed",
      "could not connect",
      "is not currently accepting connections",
      "too many connections",
      "Connection refused",
      "the database system is in recovery mode"
    ].freeze
    CONNECTION_ERROR_RE = /#{CONNECTION_ERROR.map { |w| Regexp.escape(w) }.join("|")}/.freeze

    CONNECTION_SCHEMA_ERROR = ["PG::UndefinedColumn"].freeze
    CONNECTION_SCHEMA_RE = /#{CONNECTION_SCHEMA_ERROR.map { |w| Regexp.escape(w) }.join("|")}/.freeze

    class << self
      def supported_errors?(e)
        return true if failover_error?(e.message)
        return true if missing_column_error?(e.message)
        false
      end

      def failover_error?(error_message)
        CONNECTION_ERROR_RE.match?(error_message) && ::PgAdapter.failover_patch?
      end

      def missing_column_error?(error_message)
        CONNECTION_SCHEMA_RE.match?(error_message) &&
          ::PgAdapter.reset_column_information_patch?
      end
    end

    private

    def exec_cache(*args)
      sleep_times = ::PgAdapter.configuration.reconnect_with_backoff.dup
      query, _ = args
      within_transaction = in_transaction? # capture in_transaction? state before retries
      begin
        super(*args)
      rescue ::ActiveRecord::StatementInvalid,
             ::ActiveRecord::ConnectionNotEstablished,
             ::ActiveRecord::NoDatabaseError => e
        raise unless ::PgAdapter::Patch.supported_errors?(e)
        handle_schema_cache_error(e)
        handle_activerecord_error(e)
        raise if within_transaction
        raise unless try_reconnect?(e)

        sleep_time = sleep_times.shift
        if sleep_time
          warn("Retry query failed, retrying again in #{sleep_time} sec. Retrying: #{query}")
          sleep(sleep_time)
          connect
          retry
        else
          handle_activerecord_error(e)
          raise
        end
      end
    end

    def exec_no_cache(*args)
      sleep_times = ::PgAdapter.configuration.reconnect_with_backoff.dup
      query, _ = args
      within_transaction = in_transaction? # capture in_transaction? state before retries
      begin
        super(*args)
      rescue ::ActiveRecord::StatementInvalid,
             ::ActiveRecord::ConnectionNotEstablished,
             ::ActiveRecord::NoDatabaseError => e
        raise unless ::PgAdapter::Patch.supported_errors?(e)
        handle_schema_cache_error(e)
        handle_activerecord_error(e)
        raise if within_transaction
        raise unless try_reconnect?(e)

        sleep_time = sleep_times.shift
        if sleep_time
          warn("Retry query failed, retrying again in #{sleep_time} sec. Retrying: #{query}")
          sleep(sleep_time)
          connect
          retry
        else
          handle_activerecord_error(e)
          raise
        end
      end
    end

    def try_reconnect?(e)
      return false if in_transaction?
      return false unless ::PgAdapter::Patch.failover_error?(e.message)
      return false unless ::PgAdapter.reconnect_with_backoff?
      true
    end

    def handle_activerecord_error(e)
      return unless ::PgAdapter::Patch.failover_error?(e.message)
      warn("clearing connections due to #{e} - #{e.message}")
      throw_away!
    end

    def handle_schema_cache_error(e)
      return unless ::PgAdapter::Patch.missing_column_error?(e.message)
      warn("clearing column information due to #{e} - #{e.message}")

      internal_clear_schema_cache!
      raise(e)
    end

    def internal_clear_schema_cache!
      ::ActiveRecord::Base.connection_pool.connections.each { |conn| conn.schema_cache.clear! }
      ::ActiveRecord::Base.descendants.each(&:reset_column_information)
    end

    def warn(msg)
      return unless defined?(Rails)
      return if Rails.logger.nil?
      ::Rails.logger.warn("[::PgAdapter::Patch] #{msg}")
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PgAdapter::Patch)

# Override new client connection to bake in retries
module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapter
      class << self
        old_new_client_method = instance_method(:new_client)

        define_method(:new_client) do |args|
          sleep_times = ::PgAdapter.configuration.reconnect_with_backoff.dup
          begin
            old_new_client_method.bind(self).call(args)
          rescue ::ActiveRecord::ConnectionNotEstablished, ::ActiveRecord::NoDatabaseError => e
            unless ::PgAdapter::Patch.supported_errors?(e) &&
                     ::PgAdapter.reconnect_with_backoff?
              raise
            end

            sleep_time = sleep_times.shift
            raise unless sleep_time
            warn(
              "Could not establish a connection from new_client, retrying again in #{sleep_time} sec.",
            )
            sleep(sleep_time)
            retry
          end
        end
      end
    end
  end
end
