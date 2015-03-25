# RedmineApi

Simple Object-relational mapping gem by REST API for Redmine.
http://www.redmine.org/projects/redmine/wiki/Rest_api

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redmine_api', '~> 0.0.X', github: 'taiyuf/ruby-redmine_api'
```

## Usage

### Configuration

Write the yaml file for configuration.
sample: https://github.com/taiyuf/ruby-redmine_api/blob/master/sample_configuration.yml

* uri

URL of your redmine.

* user_name

ID for Basic Authentication for your redmine.

* password

Password for Basic Authentication for your redmine.

* api_key

API Key for your redmine. Please see the document of redmine.
http://www.redmine.org/projects/redmine/wiki/Rest_api

* default_fields_format

Please set the default fields on redmine. sample is here: https://github.com/taiyuf/ruby-redmine_api/blob/master/sample_configuration.yml

The field has some parameter.

type:     Type of value on Ruby. ex. 'String', 'Fixnum', 'Hash', ....
required: true or false. If you set true, check for presence of value at valid? method.
has_id:   true or false. for example, the 'project' property has id and name, you can access by project's id. you should set the id of project by 'project_id' parameter on REST API for redmine. Please set true if the propety has id and name parameter.
on_create: true or false. Please set true if you need the property on create.
values:    Please set the Array of the pair, id and value. If the parameter is not include the value you set, the validation will fail.

* custom_fields_format

Please set the custom fields you made on redmine. sample is here: https://github.com/taiyuf/ruby-redmine_api/blob/master/sample_configuration.yml

The field has some parameter, it is same as default_fields_format.

### Sample

* Controller

```ruby
require 'redmine_api'

YourController < ApplicationController

.
.
.

def show
    config  = File.expand_path('path/to/your_config.yml', Rails.root)
    @ticket = RedmineApi::Ticket.new(config: config)
    @ticket.find(params[:id])
end

.
.
.

def create

config = File.expand_path('path/to/your_config.yml', Rails.root)
ticket = RedmineApi::Ticket.new(config: config)

if t = ticket.create(strong_parameter)
    flash[:success] = 'Success!'
    redirect_to ticket_path(t.id)
else
    render 'new'
end

.
.
.

```

* View

```ruby

.
.
.

<th>Project</th><td><%= @ticket.project_name %></td>
<th>Subject</th><td><%= @ticket.subject %></td>
<th>Description</th><td><%= @ticket.description %></td>
<th>Tracker</th><td><%= @ticket.tracker_name %></td>

.
.
.


```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/redmine_api/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
