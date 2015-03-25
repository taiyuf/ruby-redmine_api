# -*- coding: utf-8 -*-
require 'spec_helper'
require File.expand_path('../../../lib/redmine_api', __FILE__)

RSpec.describe RedmineApi::Ticket do

  before do
    @config = File.expand_path('../../sample.yml', __FILE__)
    @r      = RedmineApi::Ticket.new(config: @config)
  end

  describe 'default field method' do

    config          = File.expand_path('../../sample.yml', __FILE__)
    yaml            = YAML.load(File.read(config))
    @default_fields = yaml['default_fields_format']

    @default_fields.each do |k, v|

      if v['type'].to_s == 'Hash'

        it "has '#{k}' method ?" do
          expect(@r.respond_to?(k)).to eq(true)
        end

        it "has '#{k}_id' method ?" do
          expect(@r.respond_to?("#{k}_id")).to eq(true)
        end

        it "has '#{k}_name' method ?" do
          expect(@r.respond_to?("#{k}_name")).to eq(true)
        end


        it "#{k}_name method check" do
          @r.send(k, { name: 'fuga' })
          expect(@r.send("#{k}_name")).to eq('fuga')
        end

        it "#{k}'s value check" do
          @r.send(k, { id: 7, name: 'bar' })
          expect(@r.send(k)[:id]).to      eq(7)
          expect(@r.send(k)[:name]).to    eq('bar')
          expect(@r.send("#{k}_id")).to   eq(7)
          expect(@r.send("#{k}_name")).to eq('bar')
        end

      else

        it "has '#{k}' method ?" do
          expect(@r.respond_to?(k)).to eq(true)
        end

        it "#{k}'s value check" do
          @r.send(k, 'hoge')
          expect(@r.send("#{k}")).to eq('hoge')
        end

      end

    end

  end

  describe 'custom_fields method' do

    config         = File.expand_path('../../sample.yml', __FILE__)
    yaml           = YAML.load(File.read(config))
    @custom_fields = yaml['custom_fields_format']

    @custom_fields.each do |k, v|
      it "has '#{k}' method ?" do
        expect(@r.respond_to?(k)).to eq(true)
      end

      it "#{k}'s value check" do
        instance_eval "@r.#{k} = 'hoge'"
        expect(@r.send("#{k}")).to eq('hoge')
      end
    end
  end

  describe 'validation method' do

    describe 'private_methods' do

      it 'check_required method' do
        expect(@r.send(:check_required, :course)).to        eq(false)
        expect(@r.send(:check_required, :course, '')).to    eq(false)
        expect(@r.send(:check_required, :course_option)).to eq(true)
      end

      context 'check_type method' do

        it 'nil is allowed' do
          expect(@r.send(:check_type, :course)).to eq(true)
        end

        it 'String class' do
          expect(@r.send(:check_type, :course, 'hoge')).to eq(true)
          expect(@r.send(:check_type, :course, 1)).to      eq(false)
        end

        it 'Multiple (Array)' do
          expect(@r.send(:check_type, :course_option, ['hoge'])).to eq(true)
          expect(@r.send(:check_type, :course_option, 'hoge')).to   eq(false)
        end

        it 'Date class' do
          expect(@r.send(:check_type, :contract_date, '2015-10-15')).to eq(true)
          expect(@r.send(:check_type, :contract_date, 'hoge')).to       eq(false)
        end

        it 'Boolean class' do
          expect(@r.send(:check_type, :ps_new, '0')).to    eq(true)
          expect(@r.send(:check_type, :ps_new, '1')).to    eq(true)
          expect(@r.send(:check_type, :ps_new, '')).to     eq(true)
          expect(@r.send(:check_type, :ps_new, 'hoge')).to eq(false)
        end

      end

      it 'check_values method' do
        %w{A B C D E F}.each do |v|
          expect(@r.send(:check_values, :course, "#{v}コース")).to eq(true)
        end
        expect(@r.send(:check_values, :course, 'Gコース')).to eq(false)
        expect(@r.send(:check_values, :course)).to eq(true)
      end

    end

    describe 'check_default_fields' do

      config          = File.expand_path('../../sample.yml', __FILE__)
      yaml            = YAML.load(File.read(config))
      @default_fields = yaml['default_fields_format']

      @default_fields.each do |k, v|

        context 'default type check' do
          case v['type'].to_s

          when 'Hash'
            it "#{k} allow to set Hash" do
              @r.send(k, { id: 4, name: 'hoge' })
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
            end
            # Hashが入っているところに、Stringなどを代入しても、入らないので失敗用テストはなし

          when 'String'
            it "#{k} allow to set String" do
              @r.send(k, 'hoge')
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
            end
            it "#{k} do not allow to set String" do
              @r.send(k, 1)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
            end
          end
        end

        context '_id method check' do
          if v['type'].to_s == 'Hash'
            it "#{k}_id not allow string" do
              @r.send(k, { id: 'hoge' })
              @r.valid?
              expect(@r.errors.has_key?("#{k}_id".to_sym)).to eq(true)
            end
          end
        end

        context '.watcher_user_ids check' do
          it 'allow Array' do
            @r.watcher_user_ids = [1, 2]
            @r.valid?
            expect(@r.errors.has_key?(:watcher_user_ids)).to eq(false)
          end
          it 'do not allow Array' do
            @r.watcher_user_ids = 'hoge'
            @r.valid?
            expect(@r.errors.has_key?(:watcher_user_ids)).to eq(true)
          end
        end

      end
    end

    describe 'check_custom_fields' do

      config         = File.expand_path('../../sample.yml', __FILE__)
      yaml           = YAML.load(File.read(config))
      @custom_fields = yaml['custom_fields_format']

      @custom_fields.each do |k, v|
        context ".#{k} check required" do
          if v['required'].to_s == 'true'
            it 'Required OK' do
              @r.send("#{k}=", 'hoge')
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false) unless v['type'].to_s == 'Date' or v['values']
            end
            it 'Required NOT OK' do
              @r.send("#{k}=", nil)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
            end
          end
        end

        context ".#{k} check type" do

          case v['type'].to_s
          when 'String'
            if v['multiple'].to_s == 'true'
              it 'Multiple String OK' do
                @r.send("#{k}=", v[:values])
                @r.valid?
                expect(@r.errors.has_key?(k.to_sym)).to eq(false)
              end
              it 'Multiple String NOT OK' do
                @r.send("#{k}=", 'hoge')
                @r.valid?
                expect(@r.errors.has_key?(k.to_sym)).to eq(true)
              end
            else

              unless v['values']
                it 'String OK' do
                  @r.send("#{k}=", 'hoge')
                  @r.valid?
                  expect(@r.errors.has_key?(k.to_sym)).to eq(false)
                end
              end

            end

            it 'String NOT OK' do
              @r.send("#{k}=", 1)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
            end

          when 'Boolean'
            it 'Boolean OK' do
              @r.send("#{k}=", RedmineApi::TRUE)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
              @r.send("#{k}=", RedmineApi::FALSE)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
              unless v['values']
                # 0 or 1 制限に引っかからないように
                @r.send("#{k}=", RedmineApi::NONE)
                @r.valid?
                expect(@r.errors.has_key?(k.to_sym)).to eq(false)
              end
            end
            it 'Boolean NOT OK' do
              @r.send("#{k}=", 'hoge')
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
            end

          when 'Date'
            it 'Date OK' do
              @r.send("#{k}=", '2015-01-01')
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
            end
            it 'Date NOT OK' do
              @r.send("#{k}=", 'hoge')
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
              @r.send("#{k}=", 2)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(true)
            end

          end
        end

        if v['values']
          context "#{k} check values" do
            it 'Values OK' do
              if v['multiple']
                value = [ v['values'][0] ]
              else
                value = v['values'][0]
              end
              @r.send("#{k}=", value)
              @r.valid?
              expect(@r.errors.has_key?(k.to_sym)).to eq(false)
            end
            it 'Values NOT OK' do
              if v['multiple']
                @r.send("#{k}=", v['values'][0])
                @r.valid?
                expect(@r.errors.has_key?(k.to_sym)).to eq(true)
              else
                @r.send("#{k}=", 'hoge')
                @r.valid?
                expect(@r.errors.has_key?(k.to_sym)).to eq(true)
              end
            end
          end
        end

      end

    end

  end

  describe 'CRUD method' do

    describe 'Fake connection' do
      before do
        @config    = File.expand_path('../../../spec/sample.yml', __FILE__)
        yaml       = YAML.load(File.read(@config))
        @uri       = yaml['uri']
        @user_name = yaml['user_name']
        @password  = yaml['password']
        @api_key   = yaml['api_key']

        @r = RedmineApi::Ticket.new(config: @config)
        @r.fake_mode(true)

        body = {"issue"=>{"id"=>2, "project"=>{"id"=>4, "name"=>"システムテスト用プロジェクト"}, "tracker"=>{"id"=>1, "name"=>"バグ"}, "status"=>{"id"=>1, "name"=>"新規"}, "priority"=>{"id"=>2, "name"=>"通常"}, "author"=>{"id"=>10, "name"=>"api redmine"}, "assigned_to"=>{"id"=>10, "name"=>"api redmine"}, "subject"=>"テスト", "description"=>"テスト説明", "start_date"=>"2015-01-15", "done_ratio"=>0, "spent_hours"=>0.0, "created_on"=>"2015-01-15T01:52:43Z", "updated_on"=>"2015-01-15T01:52:43Z", "custom_fields"=>[{"id"=>21, "name"=>"契約コース", "value"=>"Bコース"}] } }

        stub_request(:get, "http://#{@user_name}:#{@password}@example.com/hoge/issues/2.json")
          .to_return(status: 200, body: body.to_json )

      end

      describe '.find' do
        before do
          @r.find(2)
        end

        it 'project' do
          expect(@r.project_id).to eq(4)
          expect(@r.project_name).to eq('システムテスト用プロジェクト')
        end
        it 'tracker' do
          expect(@r.tracker_name).to eq('バグ')
        end
        it 'priority' do
          expect(@r.priority_name).to eq('通常')
        end
        it 'author' do
          expect(@r.author_name).to eq('api redmine')
        end
        it 'assigned_to' do
          expect(@r.assigned_to_name).to eq('api redmine')
        end
        it 'subject' do
          expect(@r.subject).to eq('テスト')
        end
        it 'description' do
          expect(@r.description).to eq('テスト説明')
        end
        it 'course' do
          expect(@r.course).to eq('Bコース')
        end
      end

      describe '.create' do
        before do
          result = {"issue"=>{"id"=>52, "project"=>{"id"=>4, "name"=>"システムテスト用プロジェクト"}, "tracker"=>{"id"=>5, "name"=>"契約"}, "status"=>{"id"=>1, "name"=>"新規"}, "priority"=>{"id"=>2, "name"=>"通常"}, "author"=>{"id"=>10, "name"=>"api redmine"}, "subject"=>"テスト", "description"=>"詳細内容", "start_date"=>"2015-01-21", "done_ratio"=>0, "spent_hours"=>0.0, "custom_fields"=>[{"id"=>21, "name"=>"契約コース", "value"=>"Bコース"}, {"id"=>22, "name"=>"契約コースオプション", "multiple"=>true, "value"=>["foo", "bar"]}, {"id"=>4, "name"=>"契約開始日", "value"=>"2015-01-20"}, {"id"=>8, "name"=>"郵便番号", "value"=>"111-2222"}, {"id"=>9, "name"=>"契約者住所", "value"=>"テスト住所"}, {"id"=>17, "name"=>"新規設置かどうか", "value"=>"1"}], "created_on"=>"2015-01-21T06:44:30Z", "updated_on"=>"2015-01-21T06:44:30Z"}}

          @dummy = { project_id:    4,
                    tracker_id:    5,
                    subject:       "テストサブジェクト",
                    description:   "詳細内容",
                    priority_id:   2,
                    custom_fields: [ { id: 21, value: 'Bコース' },
                                     { id: 22, value: %w{ foo bar } },
                                     { id: 8,  value: '111-2222'},
                                     { id: 9,  value: 'テスト住所'},
                                     { id: 4,  value: '2015-01-20'},
                                     { id: 17, value: '1'}] }

          stub_request(:post, "http://#{@user_name}:#{@password}@example.com/hoge/issues.json")
            .with(
                  body:    { issue: @dummy }.to_json,
                  headers: { 'Accept'            => 'application/json',
                             'Content-Type'      => 'application/json',
                             'X-Redmine-Api-Key' => 'hoge' })
            .to_return(status:  201,
                       body:    result.to_json,
                       headers: { 'Content-Type' => 'application/json' })
          @r.create(@dummy)
        end

        it 'project' do
          expect(@r.project_id).to eq(4)
          expect(@r.project_name).to eq('システムテスト用プロジェクト')
        end
        it 'tracker' do
          expect(@r.tracker_name).to eq('契約')
        end
        it 'priority' do
          expect(@r.priority_name).to eq('通常')
        end
        it 'author' do
          expect(@r.author_name).to eq('api redmine')
        end
        it 'subject' do
          expect(@r.subject).to eq('テスト')
        end
        it 'description' do
          expect(@r.description).to eq('詳細内容')
        end
        it 'course' do
          expect(@r.course).to eq('Bコース')
        end
        it 'course_option' do
          expect(@r.course_option).to eq(%w{ foo bar })
        end
        it 'zip' do
          expect(@r.zip).to eq('111-2222')
        end
        it 'address' do
          expect(@r.address).to eq('テスト住所')
        end
        it 'contract_date' do
          expect(@r.contract_date).to eq('2015-01-20')
        end
        it 'ps_new' do
          expect(@r.ps_new).to eq('1')
        end
      end

    end
  end
end
