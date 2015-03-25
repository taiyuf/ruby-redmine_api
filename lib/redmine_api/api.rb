# -*- coding: utf-8 -*-
require 'yaml'
require 'net/http'
require 'uri'
require 'hashie'
require 'webmock'
require 'logger'

module RedmineApi

  class Api

    attr_accessor :uri,
      :scheme,
      :host,
      :port,
      :path,
      :user_name,
      :password,
      :api_key

    # Redmineでは、true => 1, false => 0, nil => ''
    TRUE                    = '1'
    FALSE                   = '0'
    NONE                    = ''
    REAL_CONNECTION_MESSAGE = 'Real connection mode.'
    FAKE_CONNECTION_MESSAGE = 'Fake connection mode.'

    def initialize(hash)

      %i{ config }.each do |sym|
        raise "#{sym} is required!" unless hash[sym]
      end

      config = hash[:config]
      raise "File is not found: #{config}." unless File.exists? config

      begin
        yaml = YAML.load(File.read(config))
      rescue
        raise "Could not load yaml: #{config}."
      else
        @@config = Hashie.symbolize_keys! yaml
      end

      # デフォルト値の設定
      parse_uri(@@config[:uri])
      self.api_key   = @@config[:api_key]   if @@config[:api_key]
      self.user_name = @@config[:user_name] if @@config[:user_name]
      self.password  = @@config[:password]  if @@config[:password]

      @fake_mode = nil
      self.fake_mode(false)

      %i{ uri api_key user_name password }.each do |f|
        if hash[f]
          if f.to_s == 'uri'
            parse_uri(hash[:uri])
          else
            instance_eval "self.#{f.to_s} = hash[:#{f}]"
          end
        end
      end

    end

    #===
    #
    # @param  Fixnum
    # @return Hash
    #
    # 渡されたIDのチケットをRedmineのAPIを叩いて取得し、Hashにして返す
    #
    # @example
    #
    # r    = RedmineApi::Api.new(config: config)
    # hash = r.get_ticket(9) # => {id: 9, project: {id: .... } }
    #
    def get_ticket(id)
      req              = make_request_get("#{self.uri}/issues/#{id}.json")
      req.content_type = 'application/json; charset=UTF-8'

      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 200
        log = Logger.new(STDOUT)
        log.debug("Error code: #{ res.code }, Error Message: #{res.message} #{ res.body }")
        return nil
      end

      Hashie.symbolize_keys!(JSON.parse(res.body))[:issue]
    end

    #===
    #
    # @param  Hash
    # @return Hash
    #
    # Net::HTTPでRedmineのAPIを叩いてチケットを作成する。作成したチケット情報をHashで返す
    #
    # @example
    #
    # r    = RedmineApi::Api.new(config: config)
    # hash = r.create_ticket(hash) # => {id: N, project: {id: .... } }
    # 
    def create_ticket(hash)
      req              = make_request_post("#{self.uri}/issues.json")
      req.content_type = 'application/json'
      req['Accept']    = 'application/json'
      req.body         = { issue: hash }.to_json

      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 201
        log = Logger.new(STDOUT)
        log.debug("Error code: #{res.code}, Error Message: #{res.message} #{res.body}")
        return false
      end

      Hashie.symbolize_keys!(JSON.parse(res.body))[:issue]
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
    # r = RedmineApi::Api.new(config: config)
    # r.delete_ticket(1) # => true or false
    #
    def delete_ticket(id)
      req = make_request_delete("#{self.uri}/issues/#{id}.json")
      res = Net::HTTP.new(self.host, self.port).start do |http| http.request(req) end

      unless res.code.to_i == 200
        log = Logger.new(STDOUT)
        log.debug("RedmineApi::Api::delete: found No ID! code: #{ res.code }, Error Message: #{res.message}, #{res.body}")
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
    #
    # r.fake_mode(true)
    # r.get_ticket(N) # => SocketError, getaddrinfo: nodename nor servname provided, or not known
    #
    def fake_mode(flag=nil)
      prefix = '*** Redmine::fake_mode:'
      log    = Logger.new(STDOUT)

      if flag.nil?

        if @fake_mode == true
          log.debug("#{prefix} #{FAKE_CONNECTION_MESSAGE}")
        else
          log.debug("#{prefix} #{REAL_CONNECTION_MESSAGE}")
        end

      else

        if flag == true
          @fake_mode = true
          WebMock.disable_net_connect!
          log.debug("#{prefix} #{FAKE_CONNECTION_MESSAGE}")
        elsif flag == false
          @fake_mode = false
          WebMock.allow_net_connect!
          log.debug("#{prefix} #{REAL_CONNECTION_MESSAGE}")
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
      req.basic_auth self.user_name, self.password if self.user_name and self.password
      req
    end

  end

end
