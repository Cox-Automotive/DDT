$:.push File.expand_path(File.join(Rails.root, %w{.. lib util xml}))
require 'yaml'
require '/opt/rh/ruby200/root/usr/local/share/gems/gems/git-1.3.0/lib/git.rb'
require 'highline/import'

module EvmGitAutomate

  def write_to_file(file, data)
    unless File.exists?(file)
      File.new(file, "w+")
    end
    File.open(file, 'w+') {|f| f.write data.to_yaml }
  end

  def import_from_file(filename)
    return YAML::load_file(filename)
  end

  def log(facility, msg)
    puts "#{facility}: #{msg}"
  end

  def config_options
    config_options = {
        'base_dir' => {
            'help' => 'Base project directory path',
            'long' => '--base_dir=<base_directory>',
            'req'  => true
        },
        'repo'     => {
            'help' => 'Git repo name (.git)',
            'long' => '--repo=<git_repo>',
            'req'  => true
        },
        'uri'     => {
            'help' => 'Git URI',
            'long' => '--uri=<git_uri>',
            'req'  => true
        },
        'branch'     => {
            'help' => 'Default git branch to use',
            'long' => '--branch=<git_default_branch>',
            'req'  => true
        },
        'log_file'     => {
            'help' => 'Log file',
            'long' => '--log_file=<log_file_path>'
        },
        'config_file'     => {
            'help' => 'Config file',
            'long' => '--config_file=<config_file_path>'
        }
    }
    config_options
  end

  def debug_pause
    input = ask 'Enter any key to continue.......'
    return true
  end

  def reject_attr(attr_hash, reject_list)
    reject_list.each do |reject|
      attr_hash.delete_if {|k, _| k == reject}
    end
    attr_hash
  end

  def validate_options(config_options, opts)
    config_options.each_key do |k|
      if config_options[k]['req'] && !opts[k]
        raise "ERROR - option: #{k} is a required option."
      end
    end
  end

  def handler(args, conf)
    opts = args.split(/\s(?=(?:[^"]|"[^"]*")*$)/)
    opts.each do |arg|
      arg.gsub!('"','')
      if conf.include?(arg.split('=')[0]) && !arg.split('=')[0].include?('--')
        arg.gsub!("#{arg}","--#{arg}")
      end
    end
    return opts
  end


  module_function :config_options
  module_function :log

end

class EvmOptions
  include(EvmGitAutomate)
  attr_reader :options

  def initialize(config, args=false)

    @config       = config
    @options      = Hash.new()

    if args
      parse(args)
    end

  end

  def parse(args, alt_config = false)
    conf = alt_config || @config
    options = Hash.new
    options['library'] = []
    options['inplace'] = false
    options['encoding'] = "utf8"
    options['transfer_type'] = :auto
    options['verbose'] = false

    opt_parser = OptionParser.new do |opts|
      #opts.banner = "Usage: tool [options]"
      conf.each_key do |option|
        long = set_long(option)
        help = set_help(option)
        short = set_short(option)
        if short
          opts.on(short, long, help) do |opt|
            @options[option] = opt
          end
        else
          opts.on(long, help) do |opt|
            @options[option] = opt
          end
        end
      end
    end

    begin
      opt_parser.parse!(args)
    rescue OptionParser::InvalidOption => e
      puts e
      return false
    rescue OptionParser::InvalidArgument => e
      puts "#{e} You must specify a correct argument. Use --help for options and arguments."
      return false
    rescue OptionParser::MissingArgument => e
      puts "#{e} You must specify a correct argument. Use --help for options and arguments."
      return false
    rescue => e
      puts "#{e} An error was encountered with the options supplied. Please ensure options are correct. Use --help for options and arguments"
      return false
    end

  end

  def set_help(option)
    conf = @config
    if conf[option].has_key?('help')
      help = conf[option]['help']
    else
      help = "#{option}"
    end
    help
  end

  def set_long(option)
    conf = @config
    if conf[option].has_key?('long')
      long = conf[option]['long']
    else
      long = "--#{option}=[OPTIONAL]"
    end
    long
  end

  def set_short(option)
    conf = @config
    if conf[option].has_key?('short')
      short = conf[option]['short']
    else
      return false
    end
    short
  end

end

class EvmGit

  include(EvmGitAutomate)
  require 'git'
  require 'logger'

  attr_reader :config
  attr_accessor :branch

  def initialize(config)

    @config  = config

    local_root = @config.root_path
    raise "Git root path not specified in: #{@config}" if local_root.nil?

    git_repo   = @config.repo
    raise "Git root repo not specified in: #{@config}" if git_repo.nil?

    init
    read_tree

  end

  def init
    begin
      if File.directory?(@config.root_path)

        message = "opening git root_path: #{@config.root_path}"
        log('info', message)

        @g      = Git.open(@config.root_path)
        @branch = current_branch

        check_branch
        read_tree

      else

        log('info', "git root_path #{@config.root_path} does not exist.")
        do_setup

      end
    rescue ArgumentError
      message = "Git root_path #{@config.root_path} does not exist."
      log('INFO', message)
      do_setup
    end
  end

  def setup_sparse_checkout
    FileUtils.cd @config.root_path
    @g.config('core.sparsecheckout', 'true')
    system "echo '#{@config.store}/' > .git/info/sparse-checkout"
    read_tree
  end

  def read_tree(tree='HEAD')
    FileUtils.cd @config.root_path
    system "git read-tree -mu #{tree}"
  end

  def do_setup

    log('INFO', "Setting up EVM Git Automate project in #{@config.root_path}.")
    system("rm -rf #{@config.root_path}/.git")
    system("rm -rf #{@config.root_path}")

    local_root = @config.root_path
    system("mkdir -p #{@config.root_path}")

    git_repo = @config.repo
    raise "Git repo not specified: #{@config}" if git_repo.nil?

    uri           = @config.uri
    repo_name     = @config.repo

    FileUtils.cd local_root

    begin
      log('INFO', "Cloning Git repo: #{repo_name} from #{uri} to #{local_root}")
      if @config.branch
        log('INFO', "Using branch #{@config.branch}")
        system "git clone #{uri} . -b #{@config.branch}"
      else
        system "git clone #{uri} ."
      end


      @g = Git.open(@config.root_path)
      FileUtils.cd @config.root_path
    rescue
      message = "ERROR cloning git repository URI: #{uri}, REPO: #{repo_name}, PATH: #{local_root}"
      log('ERROR',  message)
      raise message
    end
    unless @config.branch
      checkout_branch
    end

    setup_sparse_checkout
    pull

  end

  def file_adds_changes

    pwd = FileUtils.pwd
    FileUtils.cd @config.root_path

    @g.fetch(@g.remotes.first)

    wd = `git diff --name-only origin/#{@branch}`
    FileUtils.cd pwd

    wd.split("\n")
  end

  def checkout_branch
    FileUtils.cd @config.root_path
    system("git checkout #{@config.branch}")
    read_tree
  end

  def commit_branch
    FileUtils.cd @config.root_path
    begin
      @g.commit_all("#{Time.now} EVM Automated Commit")
    rescue
      stash
    end
  end

  def last_commit
    FileUtils.cd @config.root_path
    sha = @g.branches["origin/#{@branch}"].gcommit.sha
    sha
  end

  def add(dir=false)
    if dir
      if File.directory?(dir)
        FileUtils.cd dir
      else
        return false
      end
    else
      FileUtils.cd @config.root_path
    end
    @g.add(:all => true)
  end

  def push
    FileUtils.cd @config.root_path
    @g.push(remote = 'origin', branch = @branch, opts = {:force => true})
  end

  def pull
    FileUtils.cd @config.root_path
    begin
      @g.pull('origin', @branch)
    rescue
      log('INFO', 'Committing changes to existing model')
      commit_branch
      pull
    end
  end

  def current_branch
    current_branch = @g.current_branch
    current_branch
  end

  def set_branch(branch)
    log('INFO', "Setting current branch to #{branch}...")
    @branch = branch
    checkout_branch
    pull
  end

  def check_branch
    unless @g.current_branch == @config.branch
      log('INFO', "Git current branch will change from #{@g.current_branch} to #{@config.branch}...")
      do_setup
    end
  end

  def stash
    `git stash`
  end

  def reset_hard
    FileUtils.cd @config.root_path
    `git reset --hard`
  end

  def merge_changes
    FileUtils.cd @config.root_path
    add
    `git merge -s recursive -X theirs origin/#{current_branch}`
  end

end

class EvmGitAutomateDs
  include(EvmGitAutomate)
  attr_accessor :config

  PROJECT_ROOT = 'Datastore'

  def initialize(config)
    @config           = config
    @config.store     = PROJECT_ROOT
    @config.root_path = "#{@config.base_dir}/#{@config.store}"
    @ds_root          = @config.root_path
    @git              = EvmGit.new(@config)
  end

  def delete_domain(domain)
    d = get_domain(domain)
    raise( "Could not find domain: '#{domain}'") if d.nil?
    log('INFO', "Deleting domain ( id = #{d.id} / name = #{d.name} )")
    d.destroy
  end

  def delete_namespace(domain, namespace)
    ns = get_namespace(domain, namespace)
    raise( "Could not find namespace: '#{namespace}'in '#{domain}'") if ns.nil?
    log('INFO', "Deleting namespace ( id = #{ns.id} / name = #{ns.name} ) from /#{domain}")
    ns.destroy
  end

  def delete_class(domain, namespace, classname)
    clazz = get_class(domain, namespace, classname)
    raise( "Could not find class '#{classname}' in '/#{domain}/#{namespace}'") if clazz.nil?
    log('INFO', "Deleting class ( id = #{clazz.id} / name = #{clazz.name} ) from /#{domain}/#{namespace}")
    clazz.destroy
  end

  def delete_instance(domain, namespace, classname, instancename)
    inst = get_instance(domain, namespace, classname, instancename)
    raise( "Could not find instance: '#{instancename}' in class '/#{domain}/#{namespace}/#{classname}'") if inst.nil?
    log('INFO', "Deleting instance: ( id = #{inst.id} / name = #{inst.name} ) from /#{domain}/#{namespace}/#{classname}")
    inst.destroy
  end

  def delete_method(method)
    ae_method = get_method(method)
    raise( "Could not find method: '#{ae_method.name}' in class '/#{method.ae_domain}/#{method.ae_ns}/#{method.ae_class}'") if ae_method.nil?
    log('INFO', "Deleting method: ( id = #{method.id} / name = #{method.name} ) from /#{method.ae_domain}/#{method.ae_ns}/#{method.ae_class}")
    ae_method.destroy
  end

  def create_class(ae_class)
    ns = "#{ae_class.ae_domain}/#{ae_class.ae_ns}"
    ns = MiqAeNamespace.find_or_create_by_fqname(ns, false)
    ns.save!
    new_class = MiqAeClass.create!(:namespace_id => ns.id,
                                   :name         => ae_class.name,
                                   :description  => ae_class.name,
                                   :display_name => ae_class.name)
    new_class.save!
  end

  def create_namespace(ae_domain, ae_ns)
    begin
      ns = "#{ae_domain}/#{ae_ns}"
      ns = MiqAeNamespace.find_or_create_by_fqname(ns, false)
      ns.save!
      return ns
    rescue
      false
    end
  end

  def add_fields(ae_fields)
    ae_fields.collect do |src_field|
      attrs = src_field.attributes.reject { |k, _| DELETE_PROPERTIES.include?(k) }
      MiqAeField.new(attrs)
    end
  end

  def method_exists?(method)
    begin
      return true if get_method(method)
    rescue
      return false
    end
  end

  def import_method_data(method, data)
    ae_method = get_method(method)
    ae_method.data = data
    ae_method.save!
  end

  def get_domain(domain)
    MiqAeDomain.find_by_fqname(domain)
  end

  def get_namespace(domain, namespace)
    MiqAeNamespace.find_by_fqname( "#{domain}/#{namespace}")
  end

  def get_class(domain, namespace, classname)
    MiqAeClass.find_by_fqname( "#{domain}/#{namespace}/#{classname}")
  end

  def get_instance(domain, namespace, classname, instancename)
    MiqAeInstance.find_by_fqname( "#{domain}/#{namespace}/#{classname}/#{instancename}")
  end

  def get_method(method)
    ae_class = get_class(method.ae_domain, method.ae_ns, method.ae_class)
    ae_method = MiqAeMethod.find_by_name_and_class_id(method.name, ae_class.id)
    ae_method
  end

  def create_method(method, data = false)
    create_method_yaml(method)
  end

  def delete_method_file(method)
    file = method.local_path.gsub('.rb', '.yaml')
    FileUtils.rm method.local_path if File.exists?(method.local_path)
    FileUtils.rm file if File.exists?(file)
  end

  def create_method_yaml(method)
    file = method.local_path.gsub('.rb', '.yaml')
    unless File.exist?('file')
      File.open(file, 'w') {|f| f.write format_yaml_with(method.name).to_yaml}
    end
    return File.exist?(file)
  end

  def import_automate_class(domain, ae_ns, ae_class, path)
    log('INFO', "Importing automate class: DOMAIN: #{domain}, NAMESPACE: #{ae_ns}, CLASS: #{ae_class}")
    import_options = {'preview'   => false,
                      'mode'      => 'update',
                      'namespace' => ae_ns,
                      'class'     => ae_class,
                      'overwrite'  => true,
                      'import_as'  => nil,
                      'import_dir' => path}
    MiqAeImport.new(domain, import_options).import
  end

  def import_automate_ns(domain, ae_ns, path)

    log('INFO', "Importing automate namespace: DOMAIN: #{domain}, NAMESPACE: #{ae_ns}")
    import_options = {'preview'    => false,
                      'mode'       => 'update',
                      'namespace'  => ae_ns,
                      'overwrite'  => true,
                      'import_as'  => nil,
                      'import_dir' => path}

    MiqAeImport.new(domain, import_options).import
  end

  def export_automate_class(domain, ae_ns, ae_class, path, overwrite = 'false')

    begin
      unless get_class(domain, ae_ns, ae_class)
        log('INFO', "No class found with: DOMAIN: #{domain}, NAMESPACE: #{ae_ns}, CLASS: #{ae_class}")
        return false
      end
      log('INFO', "Exporting automate class: DOMAIN: #{domain}, NAMESPACE: #{ae_ns}, CLASS: #{ae_class}")
      rm_path = "#{path}/#{domain}/#{ae_ns}/#{ae_class}.class"
      system("rm -rf #{rm_path}")
      export_options = {'export_dir' => path,
                        'namespace'  => ae_ns,
                        'class'      => ae_class,
                        'overwrite'  => overwrite}

      MiqAeExport.new(domain, export_options).export
    rescue
      log('ERROR', "Exporting automate class. Could not export class with #{export_options}")
    end
  end

  def export_automate_ns(domain, ae_ns, path)
    log('INFO', "Exporting automate namespace: DOMAIN: #{domain}, NAMESPACE: #{ae_ns}")
    begin
      export_options = {'export_dir' => path,
                        'namespace'  => ae_ns,
                        'overwrite'  => 'true'}

      MiqAeExport.new(domain, export_options).export
    rescue
      log('ERROR', "export_automate_ns - could not export namespace with #{export_options}")
    end

  end

  def automate_backup(path)
    log('INFO', "Exporting automate model to #{path}")
    begin
      export_options = {'export_dir' => path,
                        'overwrite'  => 'true'}

      MiqAeExport.new('*', export_options).export
    rescue => e
      log('ERROR', "automate backup - could not export automate with #{export_options}")
      raise e
    end
  end

  def automate_restore(restore_path)
    log('INFO', "Restoring automate from #{restore_path}")
    log('INFO', 'It\'s a good time for a coffee break. This can take a while.')
    MiqAeDatastore.reset
    MiqAeImport.new('*', 'import_dir' => restore_path,
                    'preview'         => false,
                    'restore'         => true).import

  end

  def format_yaml_with(method_name)
    method_yaml = {}
    method_yaml['object_type']                      = 'method'
    method_yaml['version']                          = '1.0'
    method_yaml['object']                           = {}
    method_yaml['object']['attributes']             = {}
    method_yaml['object']['attributes']['name']     = method_name
    method_yaml['object']['attributes']['display_name']     = nil
    method_yaml['object']['attributes']['description']      = nil
    method_yaml['object']['attributes']['scope']            = 'instance'
    method_yaml['object']['attributes']['language']         = 'ruby'
    method_yaml['object']['attributes']['location']         = 'inline'
    method_yaml['object']['inputs']                         = []
    method_yaml
  end

  def update_methods(ae_items)
    # if method is created or updated, delete old method and add current method
    # if a method is deleted, delete method
    methods = ae_items.select{|m| m.ae_type == 'method'}

    methods.each do |method|
      if File.exists?(method.local_path)
        log('INFO', "Creating/Updating method: METHOD_NAME: #{method.name}, DOMAIN: #{method.ae_domain}, NAMESPACE: #{method.ae_ns}, CLASS: #{method.ae_class}")
        create_method(method)
      else
        log('INFO', "Deleting method: #{method.name}")
        delete_method_file(method)
      end
    end

  end

  def update_namespace(ae_items)
    ae_ns = ae_items.select{|m| m.ae_type == 'namespace'}
    ae_ns.each do |ns|
      unless File.exists?(ns.local_path)
        delete_namespace(ns.ae_domain, ns.ae_ns)
        rm_path = "#{@config.root_path}/Datastore/#{ns.ae_domain}/#{ns.ae_ns}"
        system("rm -rf #{rm_path}")
      end
    end
  end

  def update_classes(ae_items)
    ae_classes = ae_items.select{|m| m.ae_type == 'class'}
    ae_classes.each do |ae_c|
      if File.exists?(ae_c.local_path)
        # check if namespace exists
        create_namespace(ae_c.ae_domain, ae_c.ae_ns)
      else
        # Delete
        rm_path = "#{@config.root_path}/Datastore/#{ae_c.ae_domain}/#{ae_c.ae_ns}/#{ae_c.ae_class}.class"
        system("rm -rf #{rm_path}")
      end
    end
  end

  def update

    log('INFO', "Checking for method changes in git branch #{@git.current_branch}")
    all_items  = sanitize(@git.file_adds_changes.select{|f| f=~ /Datastore/}, @config.root_path)
    if all_items.empty?
      log('INFO', "No method changes in git branch: #{@git.current_branch}. Nothing to do.")
      return false
    end

    namespaces   = all_items.map{|m| "#{m.ae_domain}:#{m.ae_ns}:#{m.ae_class}"}.uniq
    namespaces.each do |ns|
      ns      = ns.split(':')
      export_automate_class(ns[0], ns[1], ns[2], "#{@config.root_path}/Datastore", 'true')
      begin
        delete_class(ns[0], ns[1], ns[2])
      rescue
        next
      end
    end

    all_items.each do |item|
      begin
        system("rm -rf #{item.local_path}") if File.exists?(item.local_path) || File.directory?(item.local_path)
      rescue
        next
      end
    end

    @git.pull

    update_namespace(all_items)
    update_classes(all_items)
    update_methods(all_items)

    namespaces.each do |ns|
      ns = ns.split(':')
      begin
        import_automate_class(ns[0], ns[1], ns[2], "#{@config.root_path}/Datastore")
      rescue
        next
      end
    end

    begin
      @git.add("#{@config.root_path}/Datastore")
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end

  end

  def export
    automate_backup("#{@config.root_path}/Datastore")
    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end
  end

  def restore
    system("rm -rf #{@config.root_path}/.git")
    system("rm -rf #{@config.root_path}")
    @git.do_setup
    automate_restore("#{@config.root_path}/Datastore")
  end

  def sanitize(items, root_path = false)
    all_ae_items = []
    items.each do |m|
      ae_domain_index = m.split('/').index('Datastore') + 1
      ae_item               = OpenStruct.new
      ae_item.ae_domain     = m.split('/')[ae_domain_index]
      ae_item.name          = m.split('/').last.gsub('.rb', '').gsub('.yaml', '')
      if root_path
        ae_item.local_path  = "#{root_path}/#{m}"
      else
        ae_item.local_path  = m
      end
      if m =~ /\.rb/
        ae_item.ae_type = 'method'
      elsif m =~ /\.yaml/ && m =~ /\.class/ && m !~ /__class__/ && m !~ /__methods__/
        ae_item.ae_type = 'instance'
      elsif m =~ /__class__\.yaml/
        ae_item.ae_type = 'class'
      elsif m =~ /__namespace__\.yaml/
        ae_item.ae_type = 'namespace'
        ae_item.name    = m.split('/')[(ae_domain_index+1)..(m.split('/').index('__namespace__.yaml'))].last
        ae_item.ae_ns   = m.split('/')[(ae_domain_index+1)..(m.split('/').index("#{ae_item.name}")-1)].join('/')
        all_ae_items << ae_item
        next
      else
        next
      end

      ae_item.ae_class      = m.split('/').select {|c| c =~ /\.class/}.first.gsub('.class', '')
      if ae_item.ae_type == 'class'
        ae_item.name = ae_item.ae_class
      end
      ae_item.ae_ns         = m.split('/')[(ae_domain_index+1)..(m.split('/').index("#{ae_item.ae_class}.class")-1)].join('/')
      all_ae_items << ae_item
    end
    all_ae_items
  end

end

class EvmGitDialog
  include(EvmGitAutomate)

  PROJECT_ROOT = 'ServiceDialogStore'

  class ParsedNonDialogYamlError < StandardError; end

  def initialize(config)
    @config           = config
    @config.store     = PROJECT_ROOT
    @config.root_path = "#{@config.base_dir}/#{@config.store}"
    @dialog_root      = "#{@config.root_path}/#{@config.store}"
    system("mkdir -p #{@dialog_root}")
    @git              = EvmGit.new @config
  end

  def export
    filedir = @dialog_root
    dialogs_hash = export_dialogs(Dialog.order(:id).all)
    dialogs_hash.each { |x|
      data = []
      data << x
      File.write("#{filedir}/#{x['label']}.yml", data.to_yaml)
    }
    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end
  end

  def restore
    dialog_items  = sanitize Dir.glob("#{@dialog_root}/**/*").select{|item| item =~ /\.yml/}
    dialog_items.each do |item|
      import item
    end
  end

  def update(local=false)
    if local
      log('INFO', "Restoring dialog data from #{@dialog_root}")
      dialog_items  = Dir.glob("#{@dialog_root}/**/*").select{|item| item =~ /\.yml/}
    else
      log('INFO', "Checking for button changes in git branch #{@git.current_branch}")
      dialog_items = @git.file_adds_changes.select{|f| f=~ /ServiceDialogStore/}
      @git.merge_changes
    end

    if dialog_items.empty?
      log('INFO', "No button changes in git branch: #{@git.current_branch}. Nothing to do.")
      return false
    end

    dialog_items = sanitize dialog_items

    dialog_items.each do |item|
      if File.exists?(item.local_path)
        import(item)
      else
        delete(item)
      end
    end
    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end

  end

  def project_root
    PROJECT_ROOT
  end

  private

  def import_dialogs_from_file(filename)
    dialogs = YAML.load_file(filename)
    import_dialogs(dialogs)
  end

  def import_dialogs(dialogs)
    begin
      dialogs.each do |d|
        puts "Dialog: [#{d['label']}]"
        dialog = Dialog.find_by_label(d["label"])
        if dialog
          dialog.update_attributes!("dialog_tabs" => import_dialog_tabs(d))
        else
          Dialog.create(d.merge("dialog_tabs" => import_dialog_tabs(d)))
        end
      end
    rescue
      raise ParsedNonDialogYamlError
    end
  end

  def import_dialog_tabs(dialog)
    dialog["dialog_tabs"].collect do |dialog_tab|
      DialogTab.create(dialog_tab.merge("dialog_groups" => import_dialog_groups(dialog_tab)))
    end
  end

  def import_dialog_groups(dialog_tab)
    dialog_tab["dialog_groups"].collect do |dialog_group|
      DialogGroup.create(dialog_group.merge("dialog_fields" => import_dialog_fields(dialog_group)))
    end
  end

  def import_dialog_fields(dialog_group)
    dialog_group["dialog_fields"].collect do |dialog_field|
      df = dialog_field['type'].constantize.create(dialog_field.reject { |a| ['resource_action_fqname'].include?(a) })
      unless dialog_field['resource_action_fqname'].blank?
        df.resource_action.fqname = dialog_field['resource_action_fqname']
        df.resource_action.save!
      end
      df
    end
  end

  def export_dialogs(dialogs)
    dialogs.map do |dialog|
      dialog_tabs = export_dialog_tabs(dialog.dialog_tabs)
      included_attributes(dialog.attributes, ["created_at", "id", "updated_at"]).merge("dialog_tabs" => dialog_tabs)
    end
  end

  def export_resource_action(resource_action)
    included_attributes(resource_action.attributes, ["created_at", "resource_id", "id", "updated_at"])
  end

  def export_dialog_fields(dialog_fields)
    dialog_fields.map do |dialog_field|
      field_attributes = included_attributes(dialog_field.attributes, ["created_at", "dialog_group_id", "id", "updated_at"])
      if dialog_field.respond_to?(:resource_action) && dialog_field.resource_action
        field_attributes["resource_action_fqname"] = dialog_field.resource_action.fqname
      end
      field_attributes
    end
  end

  def export_dialog_groups(dialog_groups)
    dialog_groups.map do |dialog_group|
      dialog_fields = export_dialog_fields(dialog_group.dialog_fields)

      included_attributes(dialog_group.attributes, ["created_at", "dialog_tab_id", "id", "updated_at"]).merge("dialog_fields" => dialog_fields)
    end
  end

  def export_dialog_tabs(dialog_tabs)
    dialog_tabs.map do |dialog_tab|
      dialog_groups = export_dialog_groups(dialog_tab.dialog_groups)

      included_attributes(dialog_tab.attributes, ["created_at", "dialog_id", "id", "updated_at"]).merge("dialog_groups" => dialog_groups)
    end
  end

  def included_attributes(attributes, excluded_attributes)
    attributes.reject { |key, _| excluded_attributes.include?(key) }
  end

  def import(item)
    Dialog.transaction do
      filename = item.local_path
      next if filename == '.' or filename == '..'
      import_dialogs_from_file("#{filename}")
    end
  end

  def delete(item)
    dialog = get_dialog(item.label)
    if dialog
      dialog.resource_actions = [] if dialog.resource_actions
      dialog.destroy
    end
  end

  def get_dialog(dialog)
    dialog = Dialog.find_by_label(dialog)
    dialog
  end

  def sanitize(items)
    all_items = []
    items.each do |i|
      item            = OpenStruct.new
      item.label      = i.split('/').last.gsub('.yml', '')
      item.name       = item.label
      item.local_path = i
      all_items << item
    end
    all_items
  end

end

class EvmGitButton
  include(EvmGitAutomate)

  PROJECT_ROOT        = 'ButtonStore'
  BUTTON_CLASSES      = %w(Vm Host ExtManagementSystem Storage EmsCluster MiqTemplate Service)
  BUTTON_OBJECT_TYPES = ['Cluster / Deployment Role', 'Datastore', 'Host / Node',
                         'Provider', 'Service', 'VM Template and Image', 'VM and Instance']

  #EXPORT_REJECT_ATTR    = [:id, :guid, :created_on, :updated_on, :created_at, :updated_at, :resource_id]
  EXPORT_REJECT_ATTR    = %w(id guid created_on updated_on created_at updated_at resource_id)
  DIALOG_ATTRIBUTES     = %w(description buttons label)
  BUTTON_SET_ATTRIBUTES = %w(name description mode owner_type owner_id userid group_id)
  BUTTON_ATTRIBUTES     = %w(name description userid wait_for_complete visibility options applies_to_class applies_to_exp applies_to_id)
  RS_ATTRIBUTES         = %w(ae_namespace ae_class ae_instance ae_message)

  def initialize(config)
    @config           = config
    @config.store     = PROJECT_ROOT
    @config.root_path = "#{@config.base_dir}/#{@config.store}"
    @button_root      = "#{@config.root_path}/#{@config.store}"
    @git              = EvmGit.new @config
  end

  def export_all
    system("rm -rf #{@button_root}")
    CustomButtonSet.all.each do |bs|
      export_button_set bs
    end
    CustomButton.all.each do |button|
      export_button button
    end
  end

  def export_button_set(button_set, export_file=false)

    export_button_set = sanitize_button_set button_set.attributes
    FileUtils.mkdir_p export_button_set.local_path

    file = export_file || "#{export_button_set.local_path}/#{export_button_set.file_name}"
    write_to_file(file, export_button_set.attributes)

  end

  def export_button(button, export_file=false)

    button_attributes = button.attributes
    if button.parent
      button_attributes['button_group']    = button.parent.name
    else
      button_attributes['button_group']    = 'Unassigned Buttons'
    end
    button_attributes['resource_action'] = button.resource_action.attributes
    export_button = sanitize_button(button_attributes)
    if export_file
      write_to_file(export_file, export_button.attributes)
    else
      FileUtils.mkdir_p export_button.local_path
      write_to_file("#{export_button.local_path}/#{export_button.file_name}", export_button.attributes)
    end

  end

  def update_buttons(local=false)
    if local
      log('INFO', "Restoring button data from #{@button_root}")
      button_items = Dir.glob("#{@button_root}/**/*").select{|item| item =~ /\.yaml/}
    else
      log('INFO', "Checking for button changes in git branch #{@git.current_branch}")
      button_items = @git.file_adds_changes.select{|f| f=~ /ButtonStore/}
      @git.merge_changes
    end

    if button_items.empty?
      log('INFO', "No button changes in git branch: #{@git.current_branch}. Nothing to do.")
      return false
    end

    process_deletes(button_items)
    process_adds(button_items)

    CustomButtonSet.all.each do |bset|
      update_button_set_order bset
    end
    export_all_to_git
  end

  def process_deletes(button_items)
    button_items.select{|item| item =~ /__group__\.yaml/}.each do |bs_file|
      #bs_file        = "#{@config.root_path}/#{bs_file}"
      unless File.exists? bs_file
        bg_class = bs_file.split('/')[-3]
        bg_name = bs_file.split('/')[-2].gsub('.group',"|#{bg_class}|")
        next if bg_name == 'Unassigned Buttons'
        log('INFO', "The button group/set: #{bg_name} will be removed")
        delete_button_set(bg_name)
      end
    end
    button_items.select{|item| item =~ /\.yaml/ && item !~ /__group__\.yaml/}.each do |b_file|
      unless File.exists? b_file
        b              = OpenStruct.new
        b.ae_class     = b_file.split('/')[-3]
        b.button_group = b_file.split('/')[-2].gsub('.group',"|#{b.ae_class}|")
        b.name         = b_file.split('/')[-1].gsub('.yaml','')
        log('INFO', "The button: #{b.name}, Button Group: #{b.button_group} will be Removed")
        delete_button(b)
      end
    end
  end

  def process_adds(button_items)
    button_items.select{|item| item =~ /__group__\.yaml/}.each do |bs_file|
      if File.exists? bs_file
        bg          = sanitize_button_set(import_from_file(bs_file))
        bg.ae_class = bg.attributes['set_data'][:applies_to_class] = bs_file.split('/')[-3]
        bg.name     = bg.attributes['name'] = bs_file.split('/')[-2].gsub('.group',"|#{bg.ae_class}|")
        bg.attributes['description'] = bg.name
        next if bg.name == 'Unassigned Buttons'
        log('INFO', "The button group/set: #{bg.name} will be updated")
        update_button_set(bg)
      end
    end
    button_items.select{|item| item =~ /\.yaml/ && item !~ /__group__\.yaml/}.each do |b_file|
      if File.exists? b_file
        b              = sanitize_button(import_from_file(b_file))
        b.ae_class     = b.attributes['applies_to_class'] = b_file.split('/')[-3]
        b.button_group = b_file.split('/')[-2].gsub('.group',"|#{b.ae_class}|")
        b.name         = b.attributes['name'] = b_file.split('/')[-1].gsub('.yaml','')
        b.attributes['description'] = b.name
        log('INFO', "The button: #{b.name}, Button Group: #{b.button_group} will be updated")
        update_button(b)
      end
    end
  end

  def export_all_to_git
    export_all
    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      log('INFO', 'No changes made to git branch.')
    end
  end

  def get_button(button)
    return CustomButton.select{|b| b.name == button.name && b.applies_to_class == button.ae_class}.first
  end

  def create_dialog(dialog)

  end

  def delete_dialog(dialog)

  end

  def get_dialog(dialog_label)
    dialog = Dialog.find_by_label dialog_label
    if dialog
      return dialog
    end
  end

  def get_dialog_label(id)
    dialog = Dialog.find id
    if dialog
      return dialog.label
    end
  end

  def get_button_set(button_set_name)
    return CustomButtonSet.find_by_name button_set_name
  end

  def update_button_set(button_set)
    n_button_set    = get_button_set(button_set.name) || CustomButtonSet.new
    attributes      = Hash.new
    BUTTON_SET_ATTRIBUTES.each do |attr|
      attributes[attr] = button_set.attributes[attr]
    end
    n_button_set.attributes = attributes
    n_button_set.set_data   = button_set.attributes['set_data'].reject {|k, _| k == :button_order}
    n_button_set.save!
    n_button_set
  end

  def delete_button_set(name)
    d_button_set = get_button_set(name)
    if d_button_set
      d_button_set.destroy
    end
  end

  def update_button(button)
    n_button    = get_button(button) || CustomButton.new
    attributes  = Hash.new
    BUTTON_ATTRIBUTES.each do |attr|
      attributes[attr] = button.attributes[attr]
    end
    n_button.attributes = attributes
    n_button.save!
    if button.attributes['resource_action']
      rsa                      = update_rsa(button.attributes['resource_action'], n_button.id)
      n_button.resource_action = rsa
    end
    parent_button_group = get_button_set(button.button_group) unless button.button_group == 'Unassigned Buttons'
    if parent_button_group
      parent_button_group.add_member n_button
    end
    n_button
  end

  def delete_button(button)
    d_button = get_button(button)
    if d_button
      rsa = d_button.resource_action
      if rsa
        rsa.destroy
      end
      d_button.destroy
    end
  end

  def update_rsa(rsa, resource_id)
    n_rsa      = get_rsa_for(resource_id) || ResourceAction.new
    attributes = Hash.new
    RS_ATTRIBUTES.each do |attr|
      attributes[attr] = rsa[attr]
    end
    n_rsa.attributes = attributes
    if rsa['ae_attributes']
      n_rsa.ae_attributes = rsa['ae_attributes']
    end
    if rsa['dialog_label']
      dialog          = get_dialog(rsa['dialog_label'])
      n_rsa.dialog    = dialog
      n_rsa.dialog_id = dialog.id
    end
    n_rsa.save!
    n_rsa
  end

  def delete_rsa(rsa)

  end

  def get_rsa_for(resource_id)
    return ResourceAction.where(resource_id: resource_id).first
  end

  def update_button_set_order(bset)
    bset.set_data[:button_order] = bset.custom_buttons.map{|b| b.id}
    bset.save!
  end

  def delete_all_button_data
    CustomButtonSet.all.each do |bg|
      bg.destroy
    end

    CustomButton.all.each do |b|
      b.destroy
    end

  end

  def sanitize_button_set(button_set, local_path = false)
    b_group                = OpenStruct.new
    b_group.ae_class       = button_set['set_data'][:applies_to_class]
    b_group.name           = button_set['name']
    b_group.attributes     = reject_attr(button_set, EXPORT_REJECT_ATTR)
    b_group.attributes['set_data'].reject! {|k, _| k == :button_order}
    b_group.local_path     = local_path || "#{@button_root}/#{b_group.ae_class}/#{b_group.name.split('|').first}.group"
    b_group.file_name      = '__group__.yaml'
    b_group
  end

  def sanitize_button(button, local_path = false)
    b                 = OpenStruct.new
    b.ae_class        = button['applies_to_class']
    b.name            = button['name']
    b.attributes      = reject_attr(button, EXPORT_REJECT_ATTR)
    b.attributes['resource_action'] = reject_attr(button['resource_action'], EXPORT_REJECT_ATTR)
    d_id = button['resource_action']['dialog_id']
    if d_id
      b.attributes['resource_action']['dialog_label'] = get_dialog_label(d_id)
    end
    b.button_group    = button['button_group']
    b.local_path      = local_path || "#{@button_root}/#{b.ae_class}/#{b.button_group.split('|').first}.group"
    b.file_name       = "#{b.name}.yaml"
    b
  end

  def update
    update_buttons
  end

  def export
    export_all_to_git
  end

  def restore
    update_buttons(local=true)
  end
end

class EvmGitTag
  include(EvmGitAutomate)
  class ParsedNonClassificationYamlError < StandardError; end

  PROJECT_ROOT        = 'TagStore'
  UPDATE_FIELDS       = ['description', 'example_text', 'show', 'perf_by_tag']

  def initialize(config)
    @config           = config
    @config.store     = PROJECT_ROOT
    @config.root_path = "#{@config.base_dir}/#{@config.store}"
    @tag_root         = "#{@config.root_path}/#{@config.store}"
    @git              = EvmGit.new @config
  end

  def update
      log('INFO', "Checking for tag changes in git branch #{@git.current_branch}")
      tag_items = @git.file_adds_changes.select{|f| f=~ /#{PROJECT_ROOT}/}

    if tag_items.empty?
      log('INFO', "No button changes in git branch: #{@git.current_branch}. Nothing to do.")
      return false
    end

    classys = tag_items.map{|tag| tag.split('/')[-2]}.uniq

    classys.each do |classy|
      classy_export(classy)
    end

    @git.merge_changes

    tag_items.each do |item|
      if item =~ /__classification__/
        if File.exists?(item)
          classy_import(item)
        else
          classy_delete(item)
        end
      else
        if File.exists?(item)
          entry          = YAML.load_file(item).stringify_keys
          item_classy    = item.split('/')[-2]
          classification = Classification.find_by_name item_classy
          next unless classification
          log('INFO', "Importing tag #{entry['name']} with classification #{item_classy}")
          import_entries(classification, [entry])
          classification.save!
        else
          tag_delete(item)
        end
      end
    end

    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end

  end

  def export
    classy_export
    begin
      @git.add
      @git.commit_branch
      @git.push
    rescue
      puts 'Completed adds/changes/deletes, no commit to branch required.'
    end
  end

  def restore
    classy_import
  end

  def import_entries(classification, entries)
    entries.each do |e|
      begin
        entry = classification.find_entry_by_name(e['name'])
        if entry
          entry.parent_id = classification.id
          entry.update_attributes!(e.select { |k| UPDATE_FIELDS.include?(k) })
          entry.save!
        else
          Classification.create(e.merge('parent_id' => classification.id))
        end
      rescue
        log('INFO', "Could not import tag #{e['name']}")
        next
      end

    end
  end

  def import_classifications(classifications)
    begin
      classifications.each do |c|
        next if ['folder_path_blue', 'folder_path_yellow'].include?(c['name'])
        log 'INFO', "Importing classification: [#{c['name']}]"
        classification = Classification.find_by_name(c['name'])
        entries        = c.delete("entries")
        if classification
          classification.update_attributes!(c.select { |k| UPDATE_FIELDS.include?(k) })
        else
          classification = Classification.create(c)
        end
        import_entries(classification, entries)
        classification.save!
      end
    rescue
      raise ParsedNonClassificationYamlError
    end
  end

  def classy_import(classy_file=false)
    classifications = []
    if classy_file
      classy_files     = [classy_file]
    else
      classy_files     = classy_file || Dir.glob("#{@tag_root}/**/*").select{|item| item =~ /__classification__/}
    end

    classy_files.each do |c|
      tags        = []
      classy_name = c.split('/')[-2]
      classy_dir  = "#{@tag_root}/#{classy_name}"
      classy_tags = Dir.glob("#{classy_dir}/**/*").select{|tag| tag !~ /__classification__/}
      classy_tags.each do |tag|
        tags << YAML.load_file(tag).stringify_keys
      end
      classy            = YAML.load_file(c).stringify_keys
      classy['entries'] = tags
      classifications << classy
    end
    import_classifications(classifications)
  end

  def classy_export(classy=false)
    classifications = YAML::load(Classification.export_to_yaml)
    if classifications && classy
      classifications = classifications.select{|c| c['name'] == classy}
    end
    unless classifications
      puts "Nothin to export"
      return false
    end

    classifications.each do |classy|
      classy       = OpenStruct.new classy
      classy_dir   = "#{@tag_root}/#{classy.name}"
      system("mkdir -p #{classy_dir}")
      classy.entries.each do |tag|
        tag      = OpenStruct.new tag
        tag_file = "#{classy_dir}/#{tag.name}.yaml"
        File.write(tag_file, tag.to_h.to_yaml)
      end
      classy.entries      = []
      classy_file         = "#{classy_dir}/__classification__.yaml"
      File.write(classy_file, classy.to_h.to_yaml)
    end
  end

  def classy_delete(classy_file)
    classy_name    = classy_file.split('/')[-2]
    classy        = Classification.find_by_name(classy_name)
    if classy
      log 'INFO', "Classification #{classy_name} will be deleted"
      classy.entries.each do |entry|
        log 'INFO', "Tag #{entry.name} with classification #{classy_name} will be deleted"
        entry.destroy
      end
      classy.destroy
    end
  end

  def tag_delete(tag_file)
    tag_classy    = tag_file.split('/')[-2]
    tag_name      = tag_file.split('/')[-1].gsub('.yaml', '')
    classy        = Classification.find_by_name(tag_classy)

    if classy
      entry = classy.find_entry_by_name(tag_name)
      if entry
        log 'INFO', "Tag #{tag_name} with classification #{tag_classy} will be deleted."
        entry.destroy
      end
    end
  end

end

class EvmGitRun
  include(EvmGitAutomate)

  attr_reader :branch
  attr_reader :methods
  attr_reader :config

  CONFIG_FILE = '/var/www/miq/vmdb/cf-git.yaml'
  PROJECT_ROOT = 'Datastore'

  def initialize(args=false)

    @config         = Hash.new
    if args
      @options      = EvmOptions.new(config_options)
      @options.parse(handler(args, config_options))
      config_options.each_key do |k|
        @config[k] = @options.options[k] unless @options.options[k].nil?
      end
    end

    if @config['config_file']
      @config    = YAML::load_file(@config['config_file'])['git'].merge(@config)
    elsif File.exists? CONFIG_FILE
      @config    =  YAML::load_file(CONFIG_FILE)['git'].merge(@config)
    else
      log('WARNING', 'No config file specified. Required options will have to be entered via cmd line.')
    end

    validate_options(config_options, @config)

    @config           = OpenStruct.new @config

  end

  def init
    EvmGitAutomateDs.new @config
    EvmGitButton.new @config
    EvmGitDialog.new(@config)
    EvmGitTag.new @config
  end

  def update_automate
    automate = EvmGitAutomateDs.new @config
    automate.update
  end

  def update_buttons
    buttons = EvmGitButton.new @config
    buttons.update
  end

  def update_dialogs
    dialogs = EvmGitDialog.new(@config)
    dialogs.update
  end

  def update_tags
    tags = EvmGitTag.new @config
    tags.update
  end


  def update_all
    update_automate
    update_buttons
    update_dialogs
    update_tags
  end

  def export_buttons
    buttons = EvmGitButton.new @config
    buttons.export
  end

  def export_dialogs
    dialogs = EvmGitDialog.new(@config)
    dialogs.export
  end

  def export_automate
    automate = EvmGitAutomateDs.new @config
    automate.export
  end

  def export_tags
    tags = EvmGitTag.new @config
    tags.export
  end

  def restore_buttons
    buttons = EvmGitButton.new @config
    buttons.delete_all_button_data
    buttons.restore
  end

  def export_all
    export_automate
    export_buttons
    export_dialogs
    export_tags
  end

  def reset_project
    @git.do_setup
    restore_automate
    restore_buttons
    restore_dialogs
    restore_tags
  end

  def restore_automate
    automate = EvmGitAutomateDs.new @config
    automate.restore
    automate.restore
  end

  def restore_dialogs
    dialogs = EvmGitDialog.new(@config)
    dialogs.restore
  end

  def restore_tags
    tags = EvmGitTag.new @config
    tags.restore
  end

end

namespace :evm do
  namespace :git do
    namespace :project do

      desc 'Initiate Git EVM Automate environment'
      task :init => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Creating evm git automate project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.init
        EvmGitAutomate.log('INFO', 'Finished creating evm git automate project...')
      end

      desc 'Update ALL project data i.e. automate model, buttons, dialogs'
      task :update => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Updating EVM Git Automate Project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.update_all
        EvmGitAutomate.log('INFO', 'Finished updating EVM Git Automate Project')
      end

      desc 'Restore EVM Git Automate Project'
      task :restore => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Resetting EVM Git Automate Project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.reset_project
        EvmGitAutomate.log('INFO', 'Finished Restoring EVM Git Automate Project')
      end

      desc 'Clear EVM Git Automate Project'

      desc 'Reset EVM Git Automate Project'
      task :export => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Exporting EVM Git Automate Project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.export_all
        EvmGitAutomate.log('INFO', 'Exporting Resetting EVM Git Automate Project')
      end

      desc 'Usage information regarding available tasks'
      task :usage => :environment do
        puts 'The following automate tasks are available ...'
        puts " Init for first time use       - Usage: rake cox:evm:project:init      BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Update all project data       - Usage: rake cox:evm:project:update    BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Reset all project data        - Usage: rake cox:evm:project:restore   BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Export all project data       - Usage: rake cox:evm:project:export    BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Clear all project data        - Usage: rake cox:evm:project:clear     BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
      end

    end
    namespace :automate do

      desc 'Initiate Git EVM Automate environment'
      task :init => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Creating evm git automate project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        EvmGitAutomate.log('INFO', 'Finished creating evm git automate project...')
      end

      desc 'Execute automate runner with options'
      task :update => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end

        EvmGitAutomate.log('INFO', 'Starting evm automate update sequence...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.update_automate
        EvmGitAutomate.log('INFO', 'Finished automate update sequence.')
      end

      desc 'Reset EVM Git Automate Project'
      task :restore => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Restoring EVM Git Automate Project...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.restore_automate
        EvmGitAutomate.log('INFO', 'Finished restoring EVM Git Automate Project')
      end

      desc 'Export automate code and import to git'
      task :export => :environment do

        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end

        EvmGitAutomate.log('INFO', 'Starting evm automate export sequence...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end

        @runner.export_automate
        EvmGitAutomate.log('INFO', 'Finished automate export sequence.')
      end

      desc 'Usage information regarding available tasks'
      task :usage => :environment do
        puts 'The following automate tasks are available ...'
        puts " Update git/automate model     - Usage: rake cox:evm:automate:update    BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Restore git/automate model    - Usage: rake cox:evm:automate:restore   BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
        puts " Export automate model to git  - Usage: rake cox:evm:automate:export    BASE_DIR='base_dir' REPO='repo' URI='uri' BRANCH='branch' LOG_FILE='log_file'"
      end

    end
    namespace :buttons do

      desc 'Usage information'
      task :usage => [:environment] do
        puts 'Export  - Usage: rake evm:git:buttons:export'
        puts 'Update  - Usage: rake evm:git:buttons:update'
        puts 'Restore - Usage: rake evm:git:buttons:restore'
      end

      desc 'Update buttons from git repository'
      task :update => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Updating buttons from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.update_buttons
        EvmGitAutomate.log('INFO', 'Finished updating buttons from git repository.')
      end

      desc 'Export buttons from git repository'
      task :export => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Exporting buttons from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.export_buttons
        EvmGitAutomate.log('INFO', 'Finished exporting buttons from git repository.')
      end

      desc 'Restoring buttons from git repository'
      task :restore => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Restoring buttons from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.restore_buttons
        EvmGitAutomate.log('INFO', 'Finished restoring buttons from git repository.')
      end

    end
    namespace :dialogs do

      desc 'Usage information'
      task :usage => [:environment] do
        puts 'Export  - Usage: rake evm:git:dialogs:export'
        puts 'Update  - Usage: rake evm:git:dialogs:update'
        puts 'Restore - Usage: rake evm:git:dialogs:restore'
      end

      desc 'Update dialogs from git repository'
      task :update => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Updating dialogs from git repository')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.update_dialogs
        EvmGitAutomate.log('INFO', 'Finished updating dialogs from git repository.')
      end

      desc 'Exporting dialogs from git repository'
      task :export => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Exporting dialogs from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.export_dialogs
        EvmGitAutomate.log('INFO', 'Finished exporting dialogs from git repository')
      end

      desc 'Restore dialogs from git repository'
      task :restore => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Restoring dialogs from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.restore_dialogs
        EvmGitAutomate.log('INFO', 'Finished restoring dialogs from git repository...')
      end

    end
    namespace :tags do

      desc 'Usage information'
      task :usage => [:environment] do
        puts 'Export  - Usage: rake evm:git:tags:export'
        puts 'Update  - Usage: rake evm:git:tags:update'
        puts 'Restore - Usage: rake evm:git:tags:restore'
      end

      desc 'Update tags from git repository'
      task :update => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Updating tags from git repository')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.update_tags
        EvmGitAutomate.log('INFO', 'Finished updating tags from git repository.')
      end

      desc 'Exporting tags from git repository'
      task :export => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Exporting tags from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.export_tags
        EvmGitAutomate.log('INFO', 'Finished exporting tags from git repository')
      end

      desc 'Restore tags from git repository'
      task :restore => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Restoring tags from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.restore_tags
        EvmGitAutomate.log('INFO', 'Finished restoring tags from git repository...')
      end

    end
    namespace :roles do

      desc 'Usage information'
      task :usage => [:environment] do
        puts 'Export  - Usage: rake evm:git:roles:export'
        puts 'Update  - Usage: rake evm:git:roles:update'
        puts 'Restore - Usage: rake evm:git:roles:restore'
      end

      desc 'Update roles from git repository'
      task :update => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Updating roles from git repository')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.update_roles
        EvmGitAutomate.log('INFO', 'Finished updating roles from git repository.')
      end

      desc 'Exporting roles from git repository'
      task :export => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Exporting roles from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.export_roles
        EvmGitAutomate.log('INFO', 'Finished exporting roles from git repository')
      end

      desc 'Restore roles from git repository'
      task :restore => :environment do
        config = ''
        config_options = EvmGitAutomate.config_options
        config_options.each_key do |k|
          config << "--#{k}=#{ENV[k.upcase]} " unless ENV[k.upcase].nil? || ENV[k.upcase].empty?
        end
        EvmGitAutomate.log('INFO', 'Restoring roles from git repository...')
        if config.empty?
          @runner = EvmGitRun.new()
        else
          @runner = EvmGitRun.new(config)
        end
        @runner.restore_roles
        EvmGitAutomate.log('INFO', 'Finished restoring roles from git repository...')
      end

    end
  end
end