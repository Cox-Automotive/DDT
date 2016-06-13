#!/usr/bin/env ruby
#####################################################################################
# Copyright 2014 Daniel Garcia <daniel.garcia@coxautoinc.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
#####################################################################################
#
# Contact Info: <daniel.garcia@coxautoinc.com> and <jd@coxautoinc.com>
#
#####################################################################################
# TODO: PRIORITY - CHECKS AND BALANCES
# TODO: create project should check for project sync fail

$:.unshift(File.expand_path(File.dirname(__FILE__) + './ansible')) unless
    $:.include?(File.dirname(__FILE__) + '.ansible') || $:.include?(File.expand_path(File.dirname(__FILE__) + '.ansible'))

require 'cf_ddt'
require 'json'
require 'yaml'
require 'highline'
require 'highline/import'
require 'faraday'
require 'faraday_middleware'
project_root = File.dirname(File.absolute_path(__FILE__))
Dir.glob(project_root + '/ansible/*') {|file| require file}

class Ansible
  include(CfDdt)
  attr_reader :parser
  JOB_TAGS  = %w(update_dialogs export_dialogs restore_dialogs update_project update_automate update_buttons export_project export_automate export_buttons restore_project restore_automate restore_buttons init)

  def initialize(config)
    @config            = config
    @connection        = Connection.new(@config)
    @config.connection = @connection
  end

  def execute
    launch @config.ansible
  end

  def init_new

    ansible_username = @config.username
    raise "Ansible user #{ansible_username} needs to be specified." unless ansible_username

    user             = User.new(@config, ansible_username)
    raise "Ansible user #{ansible_username} does not exist." unless user.exists?

    org_name       = @config.organization
    raise 'Ansible organization is required' unless org_name

    organization   = Organization.new(@config, org_name)
    raise "Ansible organization #{org_name} does not exist. Cannot create ansible environment/project." unless organization.exists?

    git_credential = @config.git_credential
    raise 'Git credential name needed to create ansible environment/project.' unless git_credential

    machine_credential   = @config.ssh_credential
    raise 'Machine (SSH) credential name needed to create ansible environment/project.' unless machine_credential

    project_name   = @config.project
    raise 'Project name needed to create ansible environment/project.' unless project_name

    inventory_name = @config.inventory
    raise 'Inventory name needed to create ansible environment/project.' unless inventory_name

    playbook_path  = @config.playbook
    raise 'Playbook path needed to create ansible environment/project.' unless playbook_path

    jbt_name       = @config.job_template
    raise 'Job template name needed to create ansible environment/project.' unless jbt_name

    hosts = @config.hosts
    raise 'Hosts need to be specifiedto create ansible environment/project' unless hosts

    #puts 'Create SCM (Git) credential'
    create_credential(user, 'scm', git_credential)

    #puts 'Create Machine (SSH) credential'
    create_credential(user, 'ssh', machine_credential)

    #puts 'Create Inventory'
    create_inventory(inventory_name, organization)

    #puts 'Create Host(s)'
    create_host(hosts, inventory_name)

    #puts 'Create Project'
    create_project(project_name, git_credential)

    #puts 'Create Job Template'
    create_job_template(jbt_name, inventory_name, project_name, machine_credential, playbook_path)

  end

  def create_project(project_name, credential)
    project             = Project.new(@config, project_name)
    credential          = Credential.new(@config, credential)
    raise "ERROR: credential #{credential} does not exist." unless credential.exists?

    if project.exists?
      puts "INFO: Project #{project.name} already exists."
      return true
    end

    project.description = project_name
    project.scm_type    = 'git'
    project.scm_branch  = @config.branch
    project.scm_url     = @config.git_url
    project.clean       = true
    project.credential  = credential.id
    project.create

    if project.exists?
      while project.status != 'successful'
        sleep(1)
        project.refresh
        raise "ERROR: project #{project_name} status is failed. Please check project details via Ansible Tower." if project.status == 'failed'
      end
      puts "INFO: Project #{project.name} created successfully"
    else
      raise "ERROR: could not create project #{project_name}"
    end
  end

  def create_inventory(inv_name, organization)
    inventory = Inventory.new(@config, inv_name)
    if inventory.exists?
      log('INFO', "Inventory #{inv_name} already exists.")
    else
      inventory.organization = organization.id
      inventory.create
      if inventory.exists?
        puts "INFO: Inventory #{inv_name} created successfully"
      else
        raise "ERROR: could not create inventory #{inv_name}"
      end
    end
  end

  def create_host(hosts, inv_name)
    inventory = Inventory.new(@config, inv_name)
    raise "ERROR: Inventory #{inv_name} does not exist. Cannot create host entry." unless inventory.exists?
    hosts.split(',').each do |host|
      host = Host.new(@config, host)
      if host.exists?
        log('INFO', "Host #{host.name} already exists.")
        next
      end
      host.inventory = inventory.id
      host.create
      raise "ERROR: host #{host.name} could not be created." unless host.exists?
      log('INFO', "Host #{host.name} was created successfully.")
    end
  end

  def create_credential(user, kind, cred_name)

    credential = Credential.new(@config, cred_name)
    if credential.exists?
      log('INFO', "Credential #{cred_name} already exists.")
    else

      log('INFO', "Creating new ansible #{kind} credential #{cred_name}")
      credential.description  = credential.name
      credential.kind         = kind
      credential.user         = user.id
      credential.username     = 'root'
      File.open(@config.path_to_rsa, 'r') do |file|
        credential.ssh_key_data = file.read
      end
      credential.create
      if credential.exists?
        log('INFO', 'Credential created successfully')
      else
        raise "Error: while creating credential #{cred_name}"
      end
    end
  end

  def create_job_template(jbt_name, inv_name, project_name, cred_name, playbook_path)
    project = Project.new(@config, project_name)
    raise "ERROR: Project #{project_name} does not exists" unless project.exists?

    credential = Credential.new(@config, cred_name)
    raise "ERROR: Credential #{cred_name} does not exists" unless credential.exists?

    inventory = Inventory.new(@config, inv_name)
    raise "ERROR: Inventory #{inv_name} does not exists" unless inventory.exists?

    playbooks = project.playbooks
    unless playbooks.include?(playbook_path)
      raise "ERROR: playbook #{playbook_path} does not exists within project #{project.name}"
    end

    job_template = JobTemplate.new(@config, jbt_name)

    if job_template.exists?
      log('INFO', "Job template #{job_template.name} already exists.")
      return true
    end

    job_template.description = job_template.name
    job_template.job_type    = 'run'

    job_template.inventory   = inventory.id
    job_template.project     = project.id

    job_template.playbook    = playbook_path
    job_template.credential  = credential.id

    job_template.verbosity   = 3
    job_template.job_tags    = operations

    job_template.create

    if job_template.exists?
      log('INFO', "Job template #{job_template.name} created successfully.")
      return true
    else
      raise "ERROR: Job template #{job_template.name} creation failed."
    end


  end

  def launch(jobs)

    hosts = @config.hosts
    if hosts
      hosts.split(',').each do |host|
        host = Host.new(@config, host)
        unless host.exists?
          create_host(host.name, @config.inventory)
        end
      end
    end

    valid_jobs  = operations
    jobs.split(',').each do |job|
      if valid_jobs.select {|jt| jt == job }.empty?
        raise "ERROR: invalid job #{job}"
      end
    end

    jbt_name           = @config.job_template
    job_template       = JobTemplate.new(@config, jbt_name)
    raise "ERROR: Job template #{jbt_name} was not found. Cannot create job." unless job_template.exists?

    job_name           = "EVM Automated task - #{Time.now}"
    job                = Job.new(@config, job_name)

    job_template.to_model_hash.each_pair do |k, v|
      job.send("#{k}=", v) unless k.to_s == 'id'
    end

    job.name          = job_name
    job.extra_vars    = extra_vars
    job.job_tags      = jobs

    job.create
    raise "ERROR: Job(s) #{jobs} could not be created" unless job.exists?

    job.start

    loop do
      sleep(1)
      job.refresh

      raise "ERROR: Operation(s) #{jobs} failed" if job.failed
      break if job.status == 'successful'
    end

    results = job.result_stdout.split('stdout').last.split("\\n")

    if results
      results[0].gsub!('": "', '')
      puts results
    end

  end

  def extra_vars
    extra_vars = {}
    %w(hosts base_dir repo uri branch log_file config_file).each do |opt|
      extra_vars[opt]=@config[opt]
    end
    extra_vars.to_yaml
  end

end
