#TODO: cf_git will be used initially to only get branch
#TODO: hosts will be specified through cmd
#TODO: maybe pull git commit after export job

class CfGit
  include CfDdt
  require 'cf_ddt/cf_git'
  require 'logger'

  attr_reader :root_path

  def initialize(root_path)
    @root_path = root_path
    init
    @branch    = current_branch
  end

  def init
    begin
      if File.directory?(@root_path)
        FileUtils.cd @root_path
        @g = Git.open(@root_path)
      else
        log('ERROR', "Git root_path #{@root_path} does not exist.")
      end
    rescue ArgumentError
      message = "Git root_path #{@root_path} does not exist."
      log('ERROR', message)
    end
  end

  def push
    FileUtils.cd @root_path
    @g.push(remote = 'origin', branch = @branch, opts = {})
  end

  def pull
    FileUtils.cd @root_path
    @g.pull('origin', @branch)
  end

  def current_branch
    current_branch = @g.current_branch
    current_branch
  end

  def url
    #return @g.remote.url
    return 'git@bitbucket.org:coxauto/cai-cloudforms-v3-production.git'
  end

  private

  def stash
    `git stash`
  end

end