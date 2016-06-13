class Host

  RESOURCE = 'hosts/'

  def initialize(config, name)
    @config     = config
    @connection = @config.connection

    @obj        = OpenStruct.new
    @obj.name   = name
    refresh
  end

  def create
    if self.exists?
      puts "INFO: Host #{self.name} already exists."
      return true
    end
    @connection.post(RESOURCE, self.to_model_hash)
    refresh
  end

  def get
    if self.exists?
      data = @connection.get("#{RESOURCE}#{self.id}/").body
    else
      data = @connection.get(RESOURCE, :name => self.name).body['results'].first
    end
    data
  end

  def refresh
    obj = get
    if obj
      @obj = OpenStruct.new self.to_model_hash.merge(obj)
    end
  end

  def self.exists?
    return true if self.id
  end

  def exists?
    return true if self.id
  end


  def self.to_model_hash
    return @obj.to_h
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