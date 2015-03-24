# -*- coding: utf-8 -*-
require 'spec_helper'
require File.expand_path('../../../lib/redmine_api', __FILE__)

RSpec.describe RedmineApi::Ticket do

  before do
    @config         = File.expand_path('../../sample.yml', __FILE__)
    @r              = RedmineApi::Ticket.new(config: @config)
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
      
    end

  end
end
