# Add the local lib directory
require 'cf_ddt'
require 'highline/import'
#TODO: log to file

class String
  def blank?
    self.strip.empty?
  end
end

module CfDdt

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
    if facility == 'ERROR'
      raise msg
    end
    puts "#{facility}: #{msg}"
  end

  def config_file
    config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), 'config/ansible_config.yml'))['global']
    config
  end

  def options
    @options     = OpenStruct.new
    @options.base = {

        'ide_project_root'     => {
            'help' => 'IDE (i.e. RubyMine project root directory)',
            'long' => '--ide_project_root=<ide_project_root_path>',
            'req'  => true
        },
        'operation'     => {
            'help' => 'Operation',
            'long' => '--operation=<operation>',
            'req'  => true
        },
        'hosts'     => {
            'help' => 'Cloudforms Host(s)',
            'long' => '--hosts=<hosts>',
            'req'  => true
        },
        'config_file' => {
            'help' => 'Ansible config file',
            'long' => '--config_file=<config file path>',
            'req'  => true
        },
        'gen_config_file' => {
            'help' => 'generate ansible config file on local path',
            'long' => '--gen_config_file',
            'req'  => true
        },
        'ansible' => {
            'help' => 'generate ansible config file on local path',
            'long' => '--ansible=<operation to perform>',
            'req'  => true
        },
        'ssh' => {
            'help' => 'generate ansible config file on local path',
            'long' => '--ssh=<operation to perform>',
            'req'  => true
        }
    }
    @options
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

  def debug_pause
    input = ask 'Enter any key to continue.......'
    return true
  end

  def operations
    return %w(update_dialogs export_dialogs restore_dialogs update_project export_project update_automate update_buttons export_project export_automate export_buttons restore_project restore_automate restore_buttons update_tags restore_tags export_tags init)

  end

  module_function :options
  module_function :log
  module_function :handler

end