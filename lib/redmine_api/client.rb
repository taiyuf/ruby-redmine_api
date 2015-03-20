# -*- coding: utf-8 -*-
require 'yaml'
require 'hashie'
require 'activemodel'

module RedmineApi

  class Client
    include ActiveModel::Model

    attr_accessor :uri,
      :scheme,
      :host,
      :port,
      :path,
      :api_key,
      :user_name,
      :password,
      :issue,
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

      begin
        yaml = YAML.load(config)
      rescue
        raise "Could not load yaml: #{config}."
      else
        @@config = Hashie.symbolize_keys! yaml
      end

      @@default_fields_format = @@config[:default_fields_format]
      @@custom_fields_format  = @@config[:custom_fields_format]
      @@default_fields_label  = []
      @@default_fields_ids    = []
      @@default_field_keys    = %i{ id name }
      @@custom_fields_label   = []
      @@custom_fields_ids     = {}

      # setup the default_fields and custom_fields.
      @@default_fields_format.each do |k, v|
        @@default_fields_label.push(k.to_sym)

        if v[:has_id].to_s == 'true'
          @@default_fields_ids.push("#{k}_id".to_sym)
        end
      end

      @@custom_fields_format.each do |k, v|
        @@custom_fields_label.push(k.to_sym)
        @@custom_fields_ids[v[:id]] = k
      end

      class_eval %q{ attr_accessor *@@custom_fields_label }

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

      @fake_mode = nil
      fake_mode(false)

      # インスタンス変数作成
      @@default_fields_format.each do |k, v|
        if v[:type] == 'Hash'
          instance_eval %Q{ @#{k} = { id: nil, name: nil } }
        end
      end

      # create_field_method

      # デフォルト値の設定
      parse_uri(@@config[:uri])
      self.api_key    = @@config[:api_key]    if @@config[:api_key]
      self.user_name  = @@config[:user_name]  if @@config[:user_name]
      self.password   = @@config[:password]   if @@config[:password]
      self.project_id = @@config[:project_id] if @@config[:project_id]

      # 引数の値を設定
      unless hash.nil?
        hash.each do |k, v|
          case k
          when :uri
            parse_uri(v)
          else
            if v.class.to_s == 'String'
              instance_eval "self.#{k} = '#{v}'"
            else
              instance_eval "self.#{k} = #{v}"
            end
          end
        end
      end
      
    end # def initialize

    #===
    #
    # @param  Fixnum
    # @return self or nil
    #
    # 引数で渡された番号のチケットをRedmineから取得し、その情報が登録されたインスタンスを返す
    # 見つからなかった場合などはnilを返す
    #
    # @example
    #
    # @redmine.find(1)
    # hoge = @redmine.hoge
    #
    def find(n)
      req = make_request_get("#{self.uri}/issues/#{n}.json")
      req.content_type = 'application/json; charset=UTF-8'
      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 200
        Rails.logger.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
        return nil
      end

      set_value_from_json(JSON.parse(res.body))
      self
    end

    #===
    #
    # @param  nil
    # @return self or nil
    #
    # ハッシュを受け取り、チケットを作成する。作成したチケット情報を自分自身に登録し、trueを、エラーが起きた時は、falseを返す
    #
    # @example
    #
    # @redmine = Remine.new( params )
    #
    # if @redmine.save
    #   .
    #   .
    #   .
    #
    def save
      create_issue if valid?
    end

    def create(hash)
      create_issue if valid?
    end

    #===
    #
    # @param  Fixnum
    # @return Boolean (true or false)
    #
    # チケットナンバーを受け取り、チケットを削除する
    #
    # @example
    #
    # json = @redmine.find(1).delete
    #
    def delete
      unless self.id
        Rails.logger.debug("Redmine::delete: found No ID!")
        raise "NO ID!"
      end

      req = make_request_delete("#{self.uri}/issues/#{self.id}.json")
      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 200
        Rails.logger.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
        return false
      end

      true
    end

    #===
    #
    # @param   Boolean
    # @return  Boolean
    # @default false
    #
    # Redmineインスタンスの、外への通信を許可するかどうか
    #
    # デフォルトはfalseで、外への通信は許可されている。trueを与えると、外への通信は許可されないため、Webmockモジュールでmock or stubで受け取らないとエラーになる
    #
    # @example
    #
    # r = Redmine.new # デフォルトは外への通信は許可
    #  .
    #  .
    #  .
    # json = r.get_issue(N) # => json = '{"issue": {"id": ... }'
    #
    # r.fake_mode(true)
    # r.get_issue(N) # => SocketError, getaddrinfo: nodename nor servname provided, or not known
    #
    def fake_mode(flag=nil)
      prefix = '*** Redmine::fake_mode:'

      if flag.nil?

        if @fake_mode == true
          Rails.logger.debug("#{prefix} #{FAKE_CONNECTION_MESSAGE}")
        else
          Rails.logger.debug("#{prefix} #{REAL_CONNECTION_MESSAGE}")
        end

      else

        if flag == true
          @fake_mode = true
          WebMock.disable_net_connect!
          Rails.logger.debug("#{prefix} #{FAKE_CONNECTION_MESSAGE}")
        elsif flag == false
          @fake_mode = false
          WebMock.allow_net_connect!
          Rails.logger.debug("#{prefix} #{REAL_CONNECTION_MESSAGE}")
        else
          raise "#{prefix} Unknown flag: #{flag}."
        end

      end

      @fake_mode
    end

    private

    #===
    #
    # @param  String
    # @return Net::HTTP::Get
    #
    # URLを受け取り、Net::HTTP::Getのリクエストを返す
    # Basic認証と、APIキーの'X-Redmine-API-Key'のヘッダーを追加している
    #
    def make_request_get(str)
      _make_request('get', str)
    end

    #===
    #
    # @param  String
    # @return Net::HTTP::Post
    #
    # URLを受け取り、Net::HTTP::Postのリクエストを返す
    # Basic認証と、APIキーの'X-Redmine-API-Key'のヘッダーを追加している
    #
    def make_request_post(str)
      _make_request('post', str)
    end

    #===
    #
    # @param  String
    # @return Net::HTTP::Delete
    #
    # URLを受け取り、Net::HTTP::のリクエストを返す
    # Basic認証と、APIキーの'X-Redmine-API-Key'のヘッダーを追加している
    #
    def make_request_delete(str)
      _make_request('delete', str)
    end

    #===
    #
    # @param  String
    # @return nil
    #
    # URIの文字列を受け取って、host, port, pathのプロパティを設定する
    #
    # @example
    #
    # self.parse_uri('http://localhost/hoge/') #=> self.scheme = 'http'
    #                                              self.host   = 'localhost'
    #                                              self.port   = 80
    #                                              self.path   = '/hoge'
    #
    def parse_uri(uri)
      uri = URI.parse(uri)
      self.scheme = uri.scheme
      self.host   = uri.host
      self.port   = uri.port
      if uri.path =~ /(.*)\/$/
        self.path = uri.path.sub(/\/$/, '')
        self.uri  = uri.to_s.sub(/\/$/, '')
      else
        self.path = uri.path
        self.uri  = uri.to_s
      end
    end

    #===
    #
    # @param  String, String
    # @return Net::HTTPRequest
    #
    def _make_request(type, str)
      url = URI.parse(str)

      if type.to_s == 'get'
        req = Net::HTTP::Get.new(url.path)
      elsif type.to_s == 'post'
        req = Net::HTTP::Post.new(url.path)
      elsif type.to_s == 'delete'
        req = Net::HTTP::Delete.new(url.path)
      else
        raise "Unknown type: #{type}."
      end
      # API認証
      req['X-Redmine-API-Key'] = self.api_key
      # Basic認証
      req.basic_auth self.user_name, self.password
      req
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
    # @param  JSON
    # @return nil
    #
    # 
    def set_value_from_json(json)

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
    # @return Self
    #
    # ハッシュを受け取り、チケットを作成する。作成したチケット情報を自分自身に登録し、自分自身を返す
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

      req = make_request_post("#{self.uri}/issues.json")
      req.content_type = 'application/json'
      req['Accept']    = 'application/json'
      req.body = self.issue.to_json
      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 201
        Rails.logger.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
        return false
      end

      set_value_from_json(JSON.parse(res.body))
      # self.id ? self.id : nil
      self
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
