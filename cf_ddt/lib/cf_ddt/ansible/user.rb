require 'faraday'
require 'faraday_middleware'

# can't reassign the id
# username needs to be name etc

class User

  RESOURCE = 'users/'

  def initialize(config, name)
    @config     = config
    @connection = @config.connection

    @obj          = OpenStruct.new
    @obj.username = name
    refresh
  end

  def get
    if self.exists?
      data = @connection.get("#{RESOURCE}#{self.id}/").body
    else
      data = @connection.get(RESOURCE, :username => self.username).body['results'].first
    end
    data
  end

  def refresh
    obj = get
    if obj
      @obj = OpenStruct.new self.to_model_hash.merge(obj)
    end
  end

  def id=
    return false
  end

  def id
    return @obj.id
  end

  def self.exists?
    return true if self.id
  end

  def exists?
    return true if self.id
  end

  def self.to_model_hash
    return  @obj.to_h
  end

  def to_model_hash
    return @obj.to_h
  end

  def method_missing(method_sym, *arguments, &block)
    begin
      super
    rescue NoMethodError
      return @obj.send(method_sym.to_s, *arguments, &block)
    end
  end

  def self.method_missing(method_sym, *arguments, &block)
    begin
      super
    rescue NoMethodError
      return @obj.send(method_sym.to_s, *arguments, &block)
    end
  end

end