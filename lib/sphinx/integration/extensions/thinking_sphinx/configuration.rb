module Sphinx::Integration::Extensions::ThinkingSphinx::Configuration
  extend ActiveSupport::Concern

  DEFAULT_MYSQL_PORT = 9306
  private_constant :DEFAULT_MYSQL_PORT

  included do
    attr_accessor :remote, :user, :password, :exclude, :ssh_port, :ssh_password,
                  :log_level, :mysql_read_timeout, :mysql_connect_timeout,
                  :start_args

    alias_method_chain :shuffled_addresses, :integration
    alias_method_chain :reset, :integration
    alias_method_chain :parse_config, :integration
    alias_method_chain :enforce_common_attribute_types, :rt
    alias_method_chain :initial_model_directories, :integration
  end

  def mysql_client
    return @mysql_client if @mysql_client

    @mysql_client = build_mysql_client(privileged: false)
  end

  def mysql_vip_client
    return @mysql_vip_client if @mysql_vip_client

    @mysql_vip_client = build_mysql_client(privileged: true)
  end

  def update_log
    @update_log ||= ::Sphinx::Integration::Mysql::QueryLog.new(namespace: "updates")
  end

  def soft_delete_log
    @soft_delete_log ||= ::Sphinx::Integration::Mysql::QueryLog.new(namespace: "soft_deletes")
  end

  def shuffled_addresses_with_integration
    Array.wrap(address)
  end

  def initial_model_directories_with_integration
    []
  end

  # Находится ли sphinx на другой машине
  #
  # Returns boolean
  def remote?
    !!remote
  end

  def reset_with_integration(custom_app_root = nil)
    self.remote = false
    self.user = 'sphinx'
    self.exclude = []
    self.log_level = "fatal"
    self.mysql_connect_timeout = 2
    self.mysql_read_timeout = 5
    self.ssh_port = 22
    self.start_args = []
    @mysql_client = nil

    reset_without_integration(custom_app_root)

    unless @configuration.searchd.binlog_path
      @configuration.searchd.binlog_path = "#{app_root}/db/sphinx/#{environment}"
    end

    if @configuration.searchd.sphinxql_state.nil? && File.exist?("#{app_root}/config/sphinx.sql")
      @configuration.searchd.sphinxql_state = "#{app_root}/config/sphinx.sql"
    end
  end

  def generated_config_file
    Rails.root.join("config", "#{Rails.env}.sphinx.conf").to_s
  end

  # Метод пришлось полностью перекрыть
  def parse_config_with_integration
    path = "#{app_root}/config/sphinx.yml"
    return unless File.exist?(path)

    conf = YAML.load(ERB.new(IO.read(path)).result)[environment]

    conf.each do |key, value|
      send("#{key}=", value) if respond_to?("#{key}=")

      set_sphinx_setting source_options, key, value, self.class::SourceOptions
      set_sphinx_setting index_options,  key, value, self.class::IndexOptions
      set_sphinx_setting index_options,  key, value, self.class::CustomOptions
      set_sphinx_setting @configuration.searchd, key, value
      set_sphinx_setting @configuration.indexer, key, value

      # добавлено заполнение секции common
      set_sphinx_setting @configuration.common, key, value
    end unless conf.nil?

    self.bin_path += '/' unless bin_path.blank?

    if allow_star
      index_options[:enable_star] = true
      index_options[:min_prefix_len] = 1
    end

    # добавлено выставление опции listen по на нашим правилам
    listen_ip = "0.0.0.0"
    mysql_port = @configuration.searchd.mysql41.is_a?(TrueClass) ? "9306" : @configuration.searchd.mysql41
    listen = [
      "#{listen_ip}:#{@configuration.searchd.port}",
      "#{listen_ip}:#{mysql_port}:mysql41"
    ]

    mysql_port_vip = @configuration.searchd.mysql41_vip.presence
    listen << "#{listen_ip}:#{mysql_port_vip}:mysql41_vip" if mysql_port_vip

    @configuration.searchd.listen = listen
  end

  # Не проверям на валидность RT индексы
  # Метод пришлось полностью переписать
  def enforce_common_attribute_types_with_rt
    sql_indexes = configuration.indices.reject do |index|
      index.is_a?(Riddle::Configuration::DistributedIndex) ||
        index.is_a?(Riddle::Configuration::RealtimeIndex)
    end

    return unless sql_indexes.any? { |index|
      index.sources.any? { |source|
        source.sql_attr_bigint.include? :sphinx_internal_id
      }
    }

    sql_indexes.each { |index|
      index.sources.each { |source|
        next if source.sql_attr_bigint.include? :sphinx_internal_id

        source.sql_attr_bigint << :sphinx_internal_id
        source.sql_attr_uint.delete :sphinx_internal_id
      }
    }
  end

  private

  def build_mysql_client(privileged: false)
    port = configuration.searchd.mysql41.presence
    port = DEFAULT_MYSQL_PORT if port.nil? || port.is_a?(TrueClass)
    vip_port = configuration.searchd.mysql41_vip.presence || port

    ::Sphinx::Integration::Mysql::Client.new(shuffled_addresses, privileged ? vip_port : port)
  end
end
