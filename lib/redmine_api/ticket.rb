# -*- coding: utf-8 -*-
require 'yaml'
require 'hashie'
require 'active_model'
require 'webmock'
require 'logger'
require_relative 'api'
require_relative 'pagination'

#=lib/redmine_api/ticket.rb
#
#== Create or Save
#
# ticket = RedmineApi::Ticket.new(config: 'path/to/config_yaml')
# ticket.create(hash)
# subject = ticket.subject
#  .
#  .
#  .
#
#  or
#
# ticket = RedmineApi::Ticket.new(config: 'path/to/config_yaml', issue: hash)
# ticket.save
# subject = ticket.subject
#  .
#  .
#  .
#
#== Find
#
# ticket = RedmineApi::Ticket.new(config: 'path/to/config_yaml')
# ticket.find(2)
# subject = ticket.subject
#  .
#  .
#  .
#
#== Delete
#
# ticket.delete or ticket.find(3).delete
#
module RedmineApi

  class Ticket
    include ActiveModel::Model

    attr_accessor :issue,
      :api,
      :values_check,
      :subject_check,
      :watcher_user_ids,
      :params,
      :issue

    ## Validation

    # default fields
    validates :project_id, presence: true, numericality: true
    validates :subject,    presence: true, if: :subject_check

    # custom fields
    validate :check_default_fields
    validate :check_custom_fields

    def initialize(hash=nil)

      %i{ config }.each do |sym|
        raise "#{sym} is required!" unless hash[sym]
      end

      # config = File.expand_path(hash[:config], Rails.root)
      config = hash[:config]
      raise "File is not found: #{config}." unless File.exists? config

      self.api = RedmineApi::Api.new(config: config)
      self.fake_mode(false)

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

      # デフォルトフィールド: project, etc....
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
          instance_eval %Q{ @#{k} = \{ id: nil, name: nil \} }
        end
      end
      @unmatch = {}

      # デフォルト値の設定
      self.project_id = @@config[:project_id] if @@config[:project_id]

      create_instance(hash[:issue]) if hash[:issue]

    end # def initialize

    def unmatch=(hash=nil)
      if hash
        if hash.class.to_s == 'Hash'
          @unmatch.merge(hash)
        else
          raise "RedmineApi::Ticket::unmatch: Hash required: #{hash}."
        end
      end

      @unmatch
    end

    alias_method :unmatch, :unmatch=

    #===
    #
    # @param  Hash
    # @return RedmineApi::Ticket Object or false
    #
    # @example
    #
    # r       = RedmineApi::Ticket.new(config: path_to_config,
    #                                  issue:  hash)
    # r.save
    # id      = r.id
    # subject = r.subject
    #
    def save
      if valid?
        create_issue
        self
      else
        false
      end

    end

    #===
    #
    # @param  Hash
    # @return RedmineApi::Ticket Object or false
    #
    # @example
    #
    # r       = RedmineApi::Ticket.new(config: path_to_config)
    # r.create(hash)
    # id      = r.id
    # subject = r.subject
    #
    def create(hash)
      create_instance(hash)

      if valid?
        create_issue
        self
      else
        false
      end

    end

    #===
    #
    # @param  Fixnum
    # @return RedmineApi::Ticket Object
    #
    # @example
    #
    # r = RedmineApi::Ticket.new(config: path_to_config)
    # r.find(2)
    # subject = r.subject
    #
    def find(id)
      create_from_json(self.api.get_ticket(id))
      self
    end

    #===
    #
    # @param  Fixnum or nil
    # @return true or false
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

      self.api.delete_ticket(self.id)
    end

    #===
    #
    # @param  true or false
    # @return true or false
    #
    # 実際にNet::HTTPで接続しに行くか、Webmockでダミー接続しに行くかのフラグを設定する
    #
    def fake_mode(flag)
      if flag
        self.api.fake_mode(flag)
      end

      self.api.fake_mode
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

      create_from_json(self.api.create_ticket(self.issue[:issue]))
      self
    end

    #===
    #
    # @param  Hash or nil
    # @return nil
    #
    def create_instance(hash)
      # 引数の値を設定
      if hash[:json]
        create_from_json(hash[:json])
      else
        hash.each do |k, v|
          case k
          when :uri
            parse_uri(v)
          when :config
          when :custom_fields
            create_custom_fields(v)
          else
            create_default_fields(k, v)
          end
        end
      end

    end

    #===
    #
    # @param  JSON
    # @return nil
    #
    # JSONの情報を元に、自分自身に情報に登録する
    #
    def create_from_json(json)

      unmatch_fields = {}
      self.issue = Hashie.symbolize_keys json

      self.issue.each do |k, v|

        if k == :custom_fields
          create_custom_fields(v)
        else
          target = @@default_fields_format[k]
          if target
            self.send(key, value)
          else
            unmatch_fields[k] = v
          end

        end
      end

      self.unmatch = unmatch_fields
      nil
    end

    #===
    #
    # @param  Array
    # @return nil
    #
    # 渡されたcustom_fieldsの配列を元に、自分自身に登録する
    #
    def create_custom_fields(array)
      unmatch_fields = {}

      array.each do |f|

        id    = f[:id]
        name  = @@custom_fields_ids[id]
        value = f[:value]

        if @@custom_fields_ids.keys.include? id

          if value.class.to_s == 'String'
            self.send("#{name}=", "#{value}")
          else
            self.send("#{name}=", value)
          end

        else
          unmatch_fields[k] = array
        end
      end

      self.unmatch = unmatch_fields
      nil
    end

    #===
    #
    # @param  nil
    # @return nil
    #
    # custom_fieldsの配列([{ id: N, value: X }, ... ])を作成し、登録する
    #
    # def publish_custom_fields
    #   array = []
    #
    #   @@custom_fields_format.each do |k, v|
    #     current = self.send(k)
    #     unless current.nil?
    #       case v[:type].to_s
    #       when 'Boolean'
    #         array.push({ id: v[:id], value: current }) if [ RedmineApi::TRUE, RedmineApi::FALSE ].include? current
    #       else
    #         array.push({ id: v[:id], value: current })
    #       end
    #     end
    #   end
    #
    #   self.custom_fields = array
    # end

    #===
    #
    # @param   Symbol, Object
    # @return  Boolean (true or false)
    # @require config/config_common.yml:custom_fields:FIELD:required true or false
    #
    # 与えられたシンボル名の値として、必須項目かどうかを required: true で判断し、true or falseを返す
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

      target = @@default_fields_format[symbol]
      target = @@custom_fields_format[symbol] unless target
      type   = target[:type]

      unless value.nil? or type.nil?

        case type.to_s
        when 'Boolean'
          return false unless [ RedmineApi::TRUE, RedmineApi::FALSE, RedmineApi::NONE ].include? value.to_s

        when 'Date'
          return false unless value.class.to_s == 'String'
          return false unless /\d+\-\d+\-\d+T?\d?+:?\d?+:?\d?+Z?/ =~ value

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

        current = self.send(k.to_s)

        # 必須チェック
        errors.add(k, ' is requied.') unless check_required(k, current)

        unless current and current.to_s == ''
          # 型チェック
          errors.add(k, " should be #{v[:type]}, #{current} (#{current.class.to_s})") unless check_type(k, current)

          # 値チェック
          if v[:values]
            if v[:multiple].to_s == 'true'
              if current.class.to_s == 'Array'
                current.each do |f|
                  errors.add(k, " should be #{v[:values]}, #{f} (#{f.class.to_s})") unless check_values(k, f)
                end
              end
            else
              errors.add(k, " should be #{v[:values]}. #{current} (#{current.class.to_s})") unless check_values(k, current)
            end
          end
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
        f   = self.send(k)
        unless f.nil? or f.to_s == ''
          errors.add(key.to_sym, " should be #{v[:type]}.") unless check_type(k, f)
        end

        # _id method
        if v[:has_id].to_s == 'true'
          key2 = "#{k}_id".to_sym
          f2   = self.send("#{k.to_s}_id")
          unless f2.nil? or f2.to_s == ''
            errors.add(key2.to_sym, " should be Number.") unless f2.class.to_s == 'Fixnum'
          end
        end

      end

      unless self.watcher_user_ids.nil? or self.watcher_user_ids.to_s == ''
        errors.add(:watcher_user_ids, " should be Array.") unless self.watcher_user_ids.class.to_s == @@default_fields_format[:watcher_user][:type]
      end

    end

  end
end

