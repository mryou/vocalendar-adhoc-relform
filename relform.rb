#!/usr/bin/env ruby1.9.1
# -*- encoding: utf-8 -*-
Encoding.default_external = 'utf-8'
require 'sinatra/base'
require 'ostruct'
require 'csv'
require 'active_support/core_ext/object/blank'
require 'fileutils'
require 'mail'

class RelForm < Sinatra::Base
  enable :logging
  enable :static
  enable :sessions

  REL_FIELDS = %w(seq type title date time producer movie_author
                  illust_author vocaloid_chars email twitter
                  description)

  @@data_dir = 'data'
  @@notify = true
  @@notify_to = 'sugi@nemui.org'
  @@notify_from = 'vocalendar@vocalendar.jp'

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    def input_text(val_name, attr_name)
      %Q{<input type="text" id="#{val_name}_#{attr_name}" name="#{val_name}[#{attr_name}]" value="#{h instance_variable_get("@#{val_name}").send(attr_name) }">}
    end
  end

  get '/' do
    @relinfo = OpenStruct.new
    erb :new
  end

  post '/create' do
    @relinfo = OpenStruct.new(params[:relinfo])
    @is_error = false

    if @relinfo.title.blank? ||
        @relinfo.producer.blank? ||
        @relinfo.date.blank? ||
        (@relinfo.twitter.blank? && @relinfo.email.blank?) ||
        @relinfo.description.blank?
      @is_error = true
    end

    @is_error and return erb :new

    File.directory?("#{@@data_dir}/images") or Dir.mkdir "#{@@data_dir}/images"

    exlock do
      begin
        seq = IO.readlines("#{@@data_dir}/seq").first.to_i + 1
        rescue Errno::ENOENT
        seq = 1
      end
      @relinfo.seq = session[:seq] = seq

      if !@relinfo.image_file.blank? && @relinfo.image_file[:tempfile]
        ext = File.extname @relinfo.image_file[:filename]
        ext.blank? and ext = "." + @relinfo.image_file[:type].split('/').last
        FileUtils.mv @relinfo.image_file[:tempfile].path, "#{@@data_dir}/images/#{"%04d" % seq}#{ext}"
      end

      CSV.open("#{@@data_dir}/relinfo.csv", "a") do |csv|
        csv << REL_FIELDS.map {|f| @relinfo.send f }
      end

      open("#{@@data_dir}/seq", "w") { |s| s << seq }
    end

    notify @relinfo

    @relinfo.image_file = nil
    session[:relinfo] = @relinfo
    redirect to('/thanks')
  end

  get '/thanks' do
    @relinfo = session[:relinfo] || OpenStruct.new
    session[:relinfo] = nil
    erb :thanks
  end

  private
  def exlock(&block)
    lockfile = "#{@@data_dir}/lock"
    File.exists?(lockfile) or File.open(lockfile, "w").close
    open(lockfile) do |f|
      f.flock File::LOCK_EX
      yield
    end
  end

  def notify(relinfo)
    @@notify or return
    Mail.deliver do
      to           @@notify_to
      from         @@notify_from
      subject      "[P-Rel] #{relinfo.title}"
      content_type 'text/plain; charset=utf-8'
      body          REL_FIELDS.map {|f| "#{f}: #{relinfo.send(f)}" }.join("\n")
    end
  end

  # start the server if ruby file executed directly
  run! if app_file == $0
end
