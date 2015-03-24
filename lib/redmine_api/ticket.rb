# -*- coding: utf-8 -*-
require 'yaml'
require 'hashie'
require 'active_model'
require 'webmock'
require 'logger'
require_relative 'api'

module RedmineApi

  class Ticket
    include ActiveModel::Model

    attr_accessor :issue,
      :api,
      :values_check,
      :subject_check,
      :watcher_user_ids,
      :params,
      :unmatch,
      :json

    ## Validation

    # default fields
    validates :project_id, presence: true, numericality: true
    validates :subject,    presence: true, if: :subject_check

    # custom fields
    validate :check_custom_fields, :check_default_fields

    # Redmineでは、true => 1, false => 0, nil => ''
    TRUE  = '1'
    FALSE = '0'
    NONE  = ''
    REAL_CONNECTION_MESSAGE = 'Real connection mode.'
    FAKE_CONNECTION_MESSAGE = 'Fake connection mode.'

    def initialize(hash=nil)

      %i{ config }.each do |sym|
        raise "#{sym} is required!" unless hash[sym]
      end

      # config = File.expand_path(hash[:config], Rails.root)
      config = hash[:config]
      raise "File is not found: #{config}." unless File.exists? config
      self.api = RedmineApi::Api.new(config: config)

      begin
        yaml = YAML.load(File.read(config))
      rescue
        raise "Could not load yaml: #{config}."
      end

      class_eval %Q{
@@config                = Hashie.symbolize_keys!(#{yaml})
@@default_fields_format = @@config[:default_fields_format]
@@custom_fields_format  = @@config[:custom_fields_format]
@@default_fields_label  = []
@@default_fields_ids    = []
@@default_field_keys    = %i{ id name }
@@custom_fields_label   = []
@@custom_fields_ids     = {}

@@default_fields_format.each do |k, v|
  @@default_fields_label.push(k.to_sym)

  if v[:has_id].to_s == 'true'
    @@default_fields_ids.push("#\{k\}_id".to_sym)
  end
end

@@custom_fields_format.each do |k, v|
  @@custom_fields_label.push(k.to_sym)
  @@custom_fields_ids[v[:id]] = k
end

attr_accessor *@@custom_fields_label
}

      # class_eval %Q{ attr_accessor #\{*@@custom_fields_label\} }

      #
      # デフォルトフィールド: project
      #
      # self.project      #=> {id: N, name: ''}
      # self.project_id   #=> self.project[:id]
      # self.project_name #=> self.project[:name]
      #
      @@default_fields_format.each do |k, v|

        if v[:type].to_s == 'Hash'

          # ex: def project, project=
          %W{ #{k} #{k}= }.each do |method|
            class_eval %Q{
def #{method}(hash=nil)
  if ! hash.nil? and hash.class.to_s == 'Hash'
    @@default_field_keys.each do |f|
      @#{k}[f] = hash[f] if hash[f]
    end
  end
  @#{k}
end
            }
          end

          # ex: def project_id, project_name
          @@default_field_keys.each do |f|
            %W{ #{k}_#{f.to_s} #{k}_#{f.to_s}= }.each do |method|
              class_eval %Q{
def #{method}(arg=nil)
  @#{k}[:#{f.to_s}] = :#{f.to_s} == :id ? arg.to_i : arg.to_s unless arg.nil?
  @#{k}[:#{f.to_s}]
end
              }
            end
          end

        else
          # ex: def subject, subject=
          %W{ #{k} #{k}= }.each do |f|
            class_eval %Q{
def #{f.to_s}(str=nil)
  @#{k} = str unless str.nil?
  @#{k}
end
            }
          end
        end

      end

      # インスタンス変数作成
      @@default_fields_format.each do |k, v|
        if v[:type] == 'Hash'
          # instance_eval %Q{ @#{k} = { id: nil, name: nil } }
          instance_eval %Q{ @#{k} = \{ id: nil, name: nil \} }
        end
      end

      # create_field_method

      # デフォルト値の設定
      # parse_uri(@@config[:uri])
      # self.api_key    = @@config[:api_key]    if @@config[:api_key]
      # self.user_name  = @@config[:user_name]  if @@config[:user_name]
      # self.password   = @@config[:password]   if @@config[:password]
      self.project_id = @@config[:project_id] if @@config[:project_id]


      create_instance(hash)

    end # def initialize

    def save(hash=nil)
      if hash
        create_instance(hash)
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
        Rails.logger.debug("Redmine::delete: found No ID!")
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

    #===
    #
    # @param  nil
    # @return Self
    #
    # Net::HTTPでRedmineのAPIを叩いてチケットを作成する。作成したチケット情報を自分自身に登録し、自分自身を返す
    #
    def create_issue
      issue         = {}
      custom_fields = []
      log = Logger.new(STDOUT)

      @@default_fields_format.each do |k, v|

        if v[:has_id].to_s == 'true'
          label   = k.to_s == 'watcher_user' ? "#{k.to_s}_ids" : "#{k.to_s}_id"
          current = self.send(label)

          if current && v[:on_create].to_s == 'true'
            issue[label.to_sym] = current
          end
        else
          issue[k] = self.send(k) if self.send(k) or ! self.send(k).nil?
         end

      end

      @@custom_fields_format.each do |k, v|
        current = self.send(k)
        custom_fields.push({id: v[:id], value: current }) if current
      end

      issue[:custom_fields] = custom_fields
      self.issue = { issue: issue }

      # req = make_request_post("#{self.uri}/issues.json")
      # req.content_type = 'application/json'
      # req['Accept']    = 'application/json'
      # req.body = self.issue.to_json
      # res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      # unless res.code.to_i == 201
      #   log.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
      #   return false
      # end

      create_from_json(@api.create_ticket(self.issue.to_json))
      # self.id ? self.id : nil
      self
    end

    #===
    #
    # @param  Hash or nil
    # @return nil
    #
    def create_instance(hash=nil)
      # 引数の値を設定
      unless hash.nil?
        if hash[:json]
          create_from_json(hash[:json])
        else
          hash.each do |k, v|
            case k
            when :uri
              parse_uri(v)
            when :config
            else
              if v.class.to_s == 'String'
                instance_eval "self.#{k} = '#{v}'"
              else
                instance_eval "self.#{k} = #{v}"
              end
            end
          end
        end
      end

    end


    #===
    #
    # @param  JSON
    # @return nil
    #
    # 
    def create_from_json(json)

      unmatch_fields = {}
      self.json = Hashie.symbolize_keys json

      self.json[:issue].each do |k, v|

        if k.to_s != 'custom_fields'
          # on default fields
          target = @@default_fields_format[k]
          if target
            if target[:type].to_s == 'Hash'
              hash = {}
              v.each do |k1, v1|
                hash[k1] = v1
              end
              self.send(k, hash)
            else
              self.send(k, v)
            end
          else
            unmatch_fields[k] = v
          end

        else
          # on custom fields => k == 'custom_fields'
          v.each do |f|

            id    = f[:id]
            name  = @@custom_fields_ids[id]
            value = f[:value]

            if @@custom_fields_ids.keys.include? id
              if value.class.to_s == 'String'
                eval "self.#{name} = '#{value}'"
              else
                eval "self.#{name} = #{value}"
              end
            else
              unmatch_fields[k] = v
            end
          end

        end

      end

      self.unmatch = unmatch_fields
    end

    #===
    #
    # @param  nil
    # @return nil
    #
    # custom_fieldsの配列([{ id: N, value: X }, ... ])を作成し、登録する
    #
    def publish_custom_fields
      array = []

      @@custom_fields_format.each do |k, v|
        current = eval "self.#{k.to_s}"
        unless current.nil?
          case v[:type]
          when 'Boolean'
            array.push({ id: v[:id], value: current }) if [ TRUE, FALSE ].include? current
          else
            array.push({ id: v[:id], value: current })
          end
        end
      end

      self.custom_fields = array
    end

    #===
    #
    # @param   Symbol, Object
    # @return  Boolean (true or false)
    # @require config/config_common.yml:custom_fields:FIELD:required true or false
    #
    # 与えられたシンボル名の値として、validかどうかをチェックし、true or falseを返す
    #
    def check_required(symbol, value=nil?)
      required = @@custom_fields_format[symbol][:required]

      if required && required.to_s == 'true'
        if value.nil? or value.to_s == '' or value == false
          return false
        end
      end

      true
    end

    #===
    #
    # @param   Symbol, Object
    # @return  Boolean (true or false)
    # @require config/config_common.yml:custom_fields:FIELD:type String
    #
    # 与えられたシンボル名の型が、指定されたものかどうかをチェックし、true or falseを返す
    #
    def check_type(symbol, value=nil)

      target = @@custom_fields_format[symbol]
      type   = target[:type]

      unless value.nil? or type.nil?

        case type.to_s
        when 'Boolean'
          return false unless [ TRUE, FALSE, NONE ].include? value.to_s

        when 'Date'
          return false unless value.class.to_s == 'String'
          return false unless /\d+\-\d+\-\d+/ =~ value

        else
          if target[:multiple] && target[:multiple].to_s == 'true'
            return false unless value.class.to_s == 'Array'
          else
            return false unless value.class.to_s == type.to_s
          end

        end

      end

      true
    end

    #===
    #
    # @param   Symbol, Object
    # @return  Boolean (true or false)
    # @require config/config_common.yml:custom_fields:FIELD:values Array
    #
    # 与えられたシンボル名の値が、指定されたものかどうかをチェックし、true or falseを返す
    #
    def check_values(symbol, value=nil)
      unless value.nil?
        return false unless @@custom_fields_format[symbol][:values].include? value.to_s
      end

      true
    end

    #===
    #
    # @param  nil
    # @return nil
    #
    # Validationのメソッド
    #
    # @example
    #
    # validate :check_custom_fields
    #
    def check_custom_fields

      @@custom_fields_format.each do |k, v|

        # current = eval "self.#{k}"
        current = self.send(k.to_s)

        # 必須チェック
        errors.add(k, 'は必須です。') unless check_required(k, current)

        # 型チェック
        errors.add(k, "の型は#{v[:type]}であるべきです。#{current} (#{current.class.to_s})") unless check_type(k, current)

        # 値チェック
        #
        # self.values_check は initializeで設定している
        #
        if self.values_check == true
          errors.add(k, "の値は#{v[:values]}であるべきです。#{current} (#{current.class.to_s})") unless check_values(k, current)
        end

      end
    end

    #===
    #
    # @param  nil
    # @return nil
    #
    # Validationのメソッド
    #
    # @example
    #
    # validate :check_default_fields
    #
    def check_default_fields

      # デフォルトの型チェック (ex: project)
      @@default_fields_format.each do |k, v|
        # defaullt
        key = k.to_sym
        f   = self.send(k.to_s)
        unless f.nil? or f.to_s == ''
          errors.add(key, "は#{v[:type]}である必要があります。") unless f.class.to_s == v[:type]
        end

        # _id method
        if v[:has_id].to_s == 'true'
          key2 = "#{k}_id".to_sym
          f2   = self.send("#{k.to_s}_id")
          unless f2.nil? or f2.to_s == ''
            errors.add(key2, "は数字である必要があります。") unless f2.class.to_s == 'Fixnum'
          end
        end

      end

      unless self.watcher_user_ids.nil? or self.watcher_user_ids.to_s == ''
        errors.add(:watcher_user_ids, "は配列である必要があります。") unless self.watcher_user_ids.class.to_s == v[:type]
      end

    end

  end
end



