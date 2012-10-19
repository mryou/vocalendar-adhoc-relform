#!/usr/bin/env ruby1.9.1
# -*- encoding: utf-8 -*-
Encoding.default_external = 'utf-8'
require 'sinatra/base'
require 'ostruct'
require 'csv'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'
require 'fileutils'
require 'mail'

class RelForm < Sinatra::Base
  REL_FIELDS = %w(seq stamp type title url producer linkurl media
                  date time movie_author illust_author vocaloid_chars
                  twitter email description)

  @@data_dir = 'data'
  @@notify = false
  @@notify_to = 'vocalendar@vocalendar.jp'
  @@notify_from = 'vocalendar@vocalendar.jp'
  @@logging = app_file == $0

  if File.readable? 'relform.conf'
    require 'yaml'
    YAML.load_file('relform.conf').each do |key, val|
      class_variable_set "@@#{key}", val
    end
  end

  enable :static
  enable :sessions
  @@logging and enable :logging

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    def input_text(val_name, attr_name)
      val = instance_variable_get("@#{val_name}")
      %Q{<input type="text" class="#{val.errors.has_key?(attr_name.to_sym) ? 'error' : ''}" id="#{val_name}_#{attr_name}" name="#{val_name}[#{attr_name}]" value="#{h val.send(attr_name) }">}
    end

    def mcheck_box(val_name, attr_name, value, label = nil)
      label ||= value
      id = "#{val_name}_#{attr_name}_#{value.gsub(/^[.a-z0-9_-]+/i){$&.codepoints.to_a.join}}"
      val = instance_variable_get("@#{val_name}")
      attr_val = val.send(attr_name)
      is_checked = !attr_val.blank? && attr_val.member?(value)
      %Q{<span class="checkbox-set"><input type="checkbox" id="#{id}" name="#{val_name}[#{attr_name}][]" value="#{h value}" #{is_checked ? 'checked="checked"' : ''}><label for="#{id}">#{h label}</label></span>}
    end
  end

  before do
    logger.info "param: #{params.inspect}"
    @relinfo = OpenStruct.new
    @relinfo.errors = {}
    def @relinfo.error?(field = nil)
      if field
        self.errors.has_key?(field.to_sym)
      else
        !self.errors.blank?
      end
    end
  end

  get '/' do
    erb :new
  end

  post '/create' do
    params[:relinfo].each do |k, v|
      @relinfo.__send__ "#{k}=", Array === v ? v.find_all {|i| !i.blank? } : v
    end
    %w(media vocaloid_chars).each do |field|
      @relinfo.__send__(field) or @relinfo.__send__("#{field}=", [])
      @relinfo.__send__("#{field}_other").blank? and next
      @relinfo.__send__(field) << @relinfo.__send__("#{field}_other")
    end

    %w(title type producer date media vocaloid_chars).each do |field|
      @relinfo.__send__(field).blank? or next
      @relinfo.errors[field.to_sym] = true
    end

    @relinfo.twitter.blank? && @relinfo.email.blank? and
      @relinfo.errors[:twitter] = @relinfo.errors[:email] = true

    @relinfo.error? and return erb :new

    File.directory?("#{@@data_dir}/images") or Dir.mkdir "#{@@data_dir}/images"

    exlock do
      begin
        seq = IO.readlines("#{@@data_dir}/seq").first.to_i + 1
        rescue Errno::ENOENT
        seq = 1
      end
      @relinfo.seq = session[:seq] = seq
      @relinfo.stamp = Time.now.strftime("%F %T")

      if !@relinfo.image_file.blank? && @relinfo.image_file[:tempfile]
        ext = File.extname @relinfo.image_file[:filename]
        ext.blank? and ext = "." + @relinfo.image_file[:type].split('/').last
        target_file = "#{@@data_dir}/images/#{"%04d" % seq}#{ext}"
        FileUtils.mv @relinfo.image_file[:tempfile].path, target_file
        File.chmod 0644, target_file
      end

      @relinfo.media = @relinfo.media.find_all {|i| !i.blank? }.join("//")
      @relinfo.vocaloid_chars = @relinfo.vocaloid_chars.find_all {|i| !i.blank? }.join("//")
      CSV.open("#{@@data_dir}/relinfo.csv", "a") do |csv|
        csv << REL_FIELDS.map {|f| @relinfo.send(f).to_s.force_encoding('utf-8').encode('shift_jis') }
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
