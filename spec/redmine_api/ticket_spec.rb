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
          expect(eval "@r.#{k}_name").to eq('fuga')
        end

        it "#{k}'s value check" do
          @r.send(k, { id: 7, name: 'bar' })
          expect(eval "@r.#{k}[:id]").to   eq(7)
          expect(eval "@r.#{k}[:name]").to eq('bar')
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
    config          = File.expand_path('../../sample.yml', __FILE__)
    yaml            = YAML.load(File.read(config))
    @custom_fields = yaml['custom_fields_format']
    @custom_fields.each do |k, v|
        it "has '#{k}' method ?" do
          expect(@r.respond_to?(k)).to eq(true)
        end

        it "#{k}'s value check" do
          # @r.send(k, 'hoge')
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

      it "#{k} allow to set id: Integer" do
          @r.send(k, { id: 4 })
          @r.valid?
          expect(@r.errors.has_key?(k)).to eq(false)
        end

        it "#{k} allow to set name: String" do
          @r.send(k, { name: 'hoge' })
          @r.valid?
          expect(@r.errors.has_key?(k)).to eq(false)
        end

        it "#{k} allow to set hash" do
          @r.send(k, { id: 4, name: 'hoge' })
          @r.valid?
          expect(@r.errors.has_key?(k)).to eq(false)
        end

        # pending "#{k}_id not allow string: 必要なのかも含め、再検討すること"

        # it "#{k}_id not allow string" do
        #   @r.send("#{k}_id", 'hoge')
        #   @r.valid?
        #   expect(@r.errors.has_key?(k)).to eq(true)
        # end

        # pending "#{k}_id method check: なぜかバリデーションが働かないので、あとで直すこと"

        # it "#{k}_id method check" do
        #   @r.send(k, { id: 4 })
        #   expect(eval "@r.#{k}_id").to eq(4)
        # end

      end
    end

    describe 'check_custom_fields' do
      
    end

  end
end
