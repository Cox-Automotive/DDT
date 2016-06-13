require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'cf_ddt'
require 'cf_ddt/ansible'

class CfOption
  include(CfDdt)

  attr_reader :options

  def initialize(config=false)
    @config = config
  end

  def parse(conf, args)
    @options            = Hash.new()
    options             = Hash.new
    options['library']  = []
    options['inplace']  = false
    options['encoding'] = "utf8"
    options['transfer_type'] = :auto
    options['verbose'] = false

    opt_parser = OptionParser.new do |opts|
      #opts.banner = "Usage: tool [options]"
      conf.each_key do |option|
        long = set_long(conf, option)
        help = set_help(conf, option)
        short = set_short(conf, option)
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

    return @options

  end

  def set_help(conf, option)
    if conf[option].has_key?('help')
      help = conf[option]['help']
    else
      help = "#{option}"
    end
    help
  end

  def set_long(conf, option)
    if conf[option].has_key?('long')
      long = conf[option]['long']
    else
      long = "--#{option}=[OPTIONAL]"
    end
    long
  end

  def set_short(conf, option)
    if conf[option].has_key?('short')
      short = conf[option]['short']
    else
      return false
    end
    short
  end

end