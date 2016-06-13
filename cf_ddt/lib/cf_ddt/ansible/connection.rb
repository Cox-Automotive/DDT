require 'faraday'
require 'faraday_middleware'

class Connection
  include(CfDdt)

  def initialize(config)

    @config   = config
    tower     = @config.tower
    raise 'ERROR: No ansible tower specified' unless tower

    @connection  = Faraday.new(:url => "https://#{tower}/api/v1/", :ssl => {:verify => false})

    @connection.request :json
    @connection.response :json

    set_token

  end

  private

  def set_token
    token = @config.token

    if token && token_valid?(token)
      @connection.authorization :Token, @config.token
    else
      token          = generate_token
      current_config = import_from_file(@config.config_file)

      save_token(current_config, token)

      @config.token  = token
      @connection.authorization :Token, token
    end
  end

  def generate_token

    username = @config.username || ask("Enter ansible username: ")
    password = @config.password || ask("Enter ansible Password: ")

    results  = @connection.post('authtoken/', {:username => username, :password => password}).body
    raise 'ERROR: Could not obtain ansible token' unless results['token']

    token    = results['token']
    @connection.authorization :Token, token

    return token

  end

  def token_valid?(token)

    @connection.authorization :Token, token
    results = @connection.get('users/').body

    if results['detail'] && (results['detail'] == 'Invalid token') || (results['detail'] == 'Token is expired')
      return false
    end

    return true
  end

  def save_token(current_config, token)
    current_config['ansible']['token'] = token
    write_to_file(@config.config_file, current_config)
  end

  def method_missing(method_sym, *arguments, &block)
    begin
      super
    rescue NoMethodError
      return @connection.send(method_sym.to_s, *arguments, &block)
    end
  end

end