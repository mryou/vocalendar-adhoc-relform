#!/usr/bin/ruby1.9.1
if File.readable? 'dispatch.rc'
 load './dispatch.rc'
end

require 'rack'
STDOUT.sync = true

load './relform.rb'

builder = Rack::Builder.new do
  run RelForm.new
end
Rack::Handler::CGI.run(builder)
