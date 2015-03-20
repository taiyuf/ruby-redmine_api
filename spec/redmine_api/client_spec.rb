require 'spec_helper'
require File.expand_path('../../../lib/redmine_api', __FILE__)

RSpec.describe RedmineApi::Client do

  describe '.initialize' do
    before do
      config = File.expand_path('../sample.yml', __FILE__)
      @r = RedmineApi::Client.new(config: config)
    end

    it do
      p "#{@r.inspect}"
    end
    
  end

end
