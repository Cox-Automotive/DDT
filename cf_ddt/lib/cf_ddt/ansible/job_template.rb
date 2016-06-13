
class JobTemplate
  include CfDdt

  RESOURCE  = 'job_templates/'
  JOB_TAGS  = %w(update_project update_automate update_buttons export_project export_automate export_buttons restore_project restore_automate restore_buttons init)


  def initialize(config, name)
    @config     = config
    @connection = @config.connection

    @obj        = OpenStruct.new
    @obj.name   = name
    refresh
  end

  def create
    if self.exists?
      log('INFO', "Job template #{self.name} already exists.")
      return true
    end
    self.extra_vars = extra_vars
    @connection.post(RESOURCE, self.to_model_hash)
    refresh
  end

  def id=
    return false
  end

  def id
    return @obj.id
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

  def extra_vars
    extra_vars = "---\nhosts: ''\nbase_dir: ''\nrepo: ''\nuri: ''\nbranch: ''\nlog_file: ''\nconfig_file: ''"
    return extra_vars
  end

end
