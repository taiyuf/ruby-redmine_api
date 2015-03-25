# -*- coding: utf-8 -*-
require 'yaml'
require 'hashie'
require 'active_model'
require 'webmock'
require 'logger'

require_relative 'ticket'
require_relative 'api'
require_relative 'pagination'

#=lib/redmine_api/client.rb
#
# r = RedmineApi::Client.new(config: config)
# r.create(params)
# @tickets = r.where(custom_field: some_word) # => Array of RedmineApi::Ticket Object
# @ticket  = r.find(1)                        # => RedmineApi::Ticket Object
# r.find(1).delete

module RedmineApi

  class Client
    include ActiveModel::Model

    attr_accessor :values_check,
      :subject_check,
      :params,
      :json

    ## Validation


    def initialize(hash=nil)

      %i{ config }.each do |sym|
        raise "#{sym} is required!" unless hash[sym]
      end

      # config = File.expand_path(hash[:config], Rails.root)
      config = hash[:config]
      raise "File is not found: #{config}." unless File.exists? config

      begin
        yaml = YAML.load(File.read(config))
      rescue
        raise "Could not load yaml: #{config}."
      else
        @@config = Hashie.symbolize_keys! yaml
      end


    end # def initialize

    def save(hash=nil)
      if hash
        RedmineApi::Ticket.new
      end

      if valid?
        create_issue
      end

      self
    end

    def create(hash)
      create_instance(hash)

      if valid?
        create_issue
      end

      self
    end

    def find(id)
      # req = make_request_get("#{self.uri}/issues/#{n}.json")
      # req.content_type = 'application/json; charset=UTF-8'
      # res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      # unless res.code.to_i == 200
      #   Rails.logger.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
      #   return nil
      # end

      create_from_json(@api.get_ticket(id))
      self
    end

    #===
    #
    # @param  Fixnum or nil
    # @return Boolean (true or false)
    #
    # チケットナンバーを受け取り、チケットを削除する
    #
    # @example
    #
    # redmine.find(1).delete
    #  or
    # redmine.delete(1)
    #
    def delete(id=nil)
      if id
        find(id)
      end

      unless self.id
        log = Logger.new(STDOUT)
        log.debug("Redmine::delete: found No ID!")
        raise "NO ID!"
      end

      # req = make_request_delete("#{self.uri}/issues/#{self.id}.json")
      # res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      # unless res.code.to_i == 200
      #   Rails.logger.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
      #   return false
      # end

      # true
      @api.delete_ticket(self.id)
    end

    private

  end


end
