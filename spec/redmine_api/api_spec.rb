# -*- coding: utf-8 -*-
require 'spec_helper'
require 'net/http'
require 'uri'
require 'json'
require 'webmock/rspec'
require File.expand_path('../../../lib/redmine_api', __FILE__)

RSpec.shared_examples "Real connection" do
  before do
    @config    = File.expand_path('../../../spec/secret.yml', __FILE__)
    yaml       = YAML.load(File.read(@config))
    @uri       = yaml['uri']
    @user_name = yaml['user_name']
    @password  = yaml['password']
    @api_key   = yaml['api_key']
    @data      = { project_id:  4,
                   subject:     'テストサブジェクト',
                   tracker_id:  5,
                   description: '詳細内容',
                   priority_id: 2,
                   custom_fields: [ {id: 21, value: 'Bコース' } ] }
    @r         = RedmineApi::Api.new(config: @config)
    @result    = @r.create_ticket(@data)
  end

  after do
    @r.delete_ticket(@result[:id])
  end

  context 'create_ticket' do

    it do
      expect(@result[:project][:id]).to  eq(4)
      expect(@result[:tracker][:id]).to  eq(5)
      expect(@result[:priority][:id]).to eq(2)
      expect(@result[:subject]).to       eq('テストサブジェクト')
      expect(@result[:description]).to   eq('詳細内容')
      cs = @result[:custom_fields]
      cs.each do |c|
        if c[:id] == 21
          expect(c[:value]).to eq('Bコース')
        end
      end
    end
  end

  context 'find' do
    it do
      @r.get_ticket(@result[:id])

      expect(@result[:project][:id]).to  eq(4)
      expect(@result[:tracker][:id]).to  eq(5)
      expect(@result[:priority][:id]).to eq(2)
      expect(@result[:subject]).to       eq('テストサブジェクト')
      expect(@result[:description]).to   eq('詳細内容')
      cs = @result[:custom_fields]
      cs.each do |c|
        if c[:id] == 21
          expect(c[:value]).to eq('Bコース')
        end
      end
    end
  end

end

RSpec.shared_examples 'Fake connection' do

  before do
    @config    = File.expand_path('../../../spec/sample.yml', __FILE__)
    yaml       = YAML.load(File.read(@config))
    @uri       = yaml['uri']
    @user_name = yaml['user_name']
    @password  = yaml['password']
    @api_key   = yaml['api_key']
  end

  let(:fake) {
    dummy = {
             project_id:  4,
             subject:     'テストサブジェクト',
             tracker_id:  5,
             description: '詳細内容',
             priority_id: 2,
             course:      'Bコース'
            }

    f = RedmineApi::Api.new(config: @config)
    f.fake_mode(true)
    f }

  describe 'create_ticket' do
    before do
      result = {"issue"=>{"id"=>52, "project"=>{"id"=>4, "name"=>"システムテスト用プロジェクト"}, "tracker"=>{"id"=>5, "name"=>"契約"}, "status"=>{"id"=>1, "name"=>"新規"}, "priority"=>{"id"=>2, "name"=>"通常"}, "author"=>{"id"=>10, "name"=>"api redmine"}, "subject"=>"テストサブジェクト", "description"=>"詳細内容", "start_date"=>"2015-01-21", "done_ratio"=>0, "spent_hours"=>0.0, "custom_fields"=>[{"id"=>21, "name"=>"契約コース", "value"=>"Bコース"}, {"id"=>22, "name"=>"契約コースオプション", "multiple"=>true, "value"=>["foo", "bar"]}, {"id"=>1, "name"=>"契約書番号", "value"=>"1111111"}, {"id"=>3, "name"=>"受付日", "value"=>"2015-01-18"}, {"id"=>4, "name"=>"契約開始日", "value"=>"2015-01-20"}, {"id"=>5, "name"=>"契約確認日", "value"=>"2015-01-19"}, {"id"=>6, "name"=>"契約者名", "value"=>"テスト契約者"}, {"id"=>7, "name"=>"法人名", "value"=>"テスト所属会社"}, {"id"=>8, "name"=>"郵便番号", "value"=>"111-2222"}, {"id"=>9, "name"=>"契約者住所", "value"=>"テスト住所"}, {"id"=>17, "name"=>"新規設置かどうか", "value"=>"1"} ], "created_on"=>"2015-01-21T06:44:30Z", "updated_on"=>"2015-01-21T06:44:30Z"}}

      @dummy = { project_id:    4,
                 tracker_id:    5,
                 subject:       "テストサブジェクト",
                 description:   "詳細内容",
                 priority_id:   2,
                 custom_fields: [ { id: 21, value: 'Bコース' } ] }

      stub_request(:post, "http://#{@user_name}:#{@password}@example.com/hoge/issues.json")
        .with(
              body:    { issue: @dummy }.to_json,
              headers: { 'Accept'            => 'application/json',
                         'Content-Type'      => 'application/json',
                         'X-Redmine-Api-Key' => 'hoge' })
        .to_return(status:  201,
                   body:    result.to_json,
                   headers: { 'Content-Type' => 'application/json' })

    end

    it do
      hash = fake.create_ticket(@dummy)
      expect(hash[:project][:id]).to  eq(4)
      expect(hash[:tracker][:id]).to  eq(5)
      expect(hash[:priority][:id]).to eq(2)
      expect(hash[:subject]).to       eq('テストサブジェクト')
      expect(hash[:description]).to   eq('詳細内容')
      cs = hash[:custom_fields]
      cs.each do |c|
        if c[:id] == 21
          expect(c[:value]).to eq('Bコース')
        end
      end
    end
  end

  describe 'get_ticket' do
    before do
      body = {"issue"=>{"id"=>2, "project"=>{"id"=>4, "name"=>"システムテスト用プロジェクト"}, "tracker"=>{"id"=>1, "name"=>"バグ"}, "status"=>{"id"=>1, "name"=>"新規"}, "priority"=>{"id"=>2, "name"=>"通常"}, "author"=>{"id"=>10, "name"=>"api redmine"}, "assigned_to"=>{"id"=>10, "name"=>"api redmine"}, "subject"=>"テスト", "description"=>"テスト説明", "start_date"=>"2015-01-15", "done_ratio"=>0, "spent_hours"=>0.0, "created_on"=>"2015-01-15T01:52:43Z", "updated_on"=>"2015-01-15T01:52:43Z"}}

      stub_request(:get, "http://#{@user_name}:#{@password}@example.com/hoge/issues/2.json")
        .to_return(status: 200, body: body.to_json )
    end

    it do
      hash = fake.get_ticket(2)
      expect(hash[:project][:name]).to  eq('システムテスト用プロジェクト')
      expect(hash[:subject]).to          eq('テスト')
    end
  end
end


RSpec.describe RedmineApi::Api do

  before do
    @config = File.expand_path('../../../spec/sample.yml', __FILE__)
  end

  let(:fake) { f = RedmineApi::Api.new({ config: @config })
    f.fake_mode(true)
    f }

  describe '.initialize' do

    context 'from config' do
      it 'scheme' do
        expect(fake.scheme).to eq('http')
      end

      it 'host' do
        expect(fake.host).to eq('example.com')
      end

      it 'port' do
        expect(fake.port).to eq(80)
      end

      it 'uri' do
        expect(fake.uri).to eq('http://example.com/hoge')
      end

      it 'api_key' do
        expect(fake.api_key).to eq('hoge')
      end

      it 'user_name' do
        expect(fake.user_name).to eq('foo')
      end

      it 'password' do
        expect(fake.password).to eq('bar')
      end
    end

    context 'override' do
      before do
        @fake = RedmineApi::Api.new(config:    @config,
                                    uri:       'https://hoge.com/fuga',
                                    api_key:   'foo1',
                                    user_name: 'foo2',
                                    password:  'foo3')
        @fake.fake_mode(true)
      end
      it 'scheme' do
        expect(@fake.scheme).to eq('https')
      end

      it 'host' do
        expect(@fake.host).to eq('hoge.com')
      end

      it 'port' do
        expect(@fake.port).to eq(443)
      end

      it 'uri' do
        expect(@fake.uri).to eq('https://hoge.com/fuga')
      end

      it 'api_key' do
        expect(@fake.api_key).to eq('foo1')
      end

      it 'user_name' do
        expect(@fake.user_name).to eq('foo2')
      end

      it 'password' do
        expect(@fake.password).to eq('foo3')
      end

    end
  end

  # include_examples 'Real connection'
  include_examples 'Fake connection'

end
