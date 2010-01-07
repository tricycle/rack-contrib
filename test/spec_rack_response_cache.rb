require 'test/spec'
require 'rack/mock'
#require 'rack/contrib/response_cache'
require File.join(File.dirname(__FILE__), '../lib/rack/contrib/response_cache')
require 'fileutils'

context Rack::ResponseCache do
  F = ::File

  def request(opts={}, &block)
    Rack::MockRequest.new(Rack::ResponseCache.new(block||@def_app, opts[:cache]||@cache, &opts[:rc_block])).send(opts[:meth]||:get, opts[:path]||@def_path, opts[:headers]||{})
  end

  setup do
    @cache = {}
    @def_disk_cache = F.join(F.dirname(__FILE__), 'response_cache_test_disk_cache')
    @def_value = ["rack-response-cache"]
    @def_path = '/path/to/blah'
    @def_app = lambda { |env| [200, {'Content-Type' => env['CT'] || 'text/html'}, @def_value]}
  end
  teardown do
    FileUtils.rm_rf(@def_disk_cache)
  end

  specify "should cache results to disk if cache is a string" do
    request(:cache => @def_disk_cache)
    F.read(F.join(@def_disk_cache, 'path', 'to', 'blah.html')).should.equal @def_value.first
    request(:path => '/path/3', :cache => @def_disk_cache)
    F.read(F.join(@def_disk_cache, 'path', '3.html')).should.equal @def_value.first
  end

  specify "should cache results to given cache if cache is not a string" do
    request
    @cache.should.equal('/path/to/blah.html' => @def_value)
    request(:path => '/path/3')
    @cache.should.equal('/path/to/blah.html' => @def_value, '/path/3.html' => @def_value)
  end

  specify "should not cache results if request method is not GET" do
    request(:meth => :post)
    @cache.should.equal({})
    request(:meth => :put)
    @cache.should.equal({})
    request(:meth => :delete)
    @cache.should.equal({})
  end

  specify "should not cache results if there is a non-empty query string" do
    request(:path => '/path/to/blah?id=1')
    @cache.should.equal({})
    request(:path => '/path/to/?id=1')
    @cache.should.equal({})
    request(:path => '/?id=1')
    @cache.should.equal({})
  end

  specify "should cache results if there is an empty query string" do
    request(:path => '/?')
    @cache.should.equal('/index.html' => @def_value)
  end

  specify "should not cache results if the request is not sucessful (status 200)" do
    request{|env| [404, {'Content-Type' => 'text/html'}, ['']]}
    @cache.should.equal({})
    request{|env| [500, {'Content-Type' => 'text/html'}, ['']]}
    @cache.should.equal({})
    request{|env| [302, {'Content-Type' => 'text/html'}, ['']]}
    @cache.should.equal({})
  end
  
  specify 'should not cache when "no cache" cache control directives' do
    request{|env| [200, {'Content-Type' => 'text/html', 'Cache-Control' => 'no-cache'}, ['']]}
    @cache.should.equal({})
  end
  
  specify 'should not cache when "private" cache control directives' do
    request{|env| [200, {'Content-Type' => 'text/html', 'Cache-Control' => 'private'}, ['']]}
    request{|env| [200, {'Content-Type' => 'text/html', 'Cache-Control' => "private, max-age=0, must-revalidate"}, ['']]}
    @cache.should.equal({})
  end
  
  specify 'should cache requests when is "public" cache control directives' do
    request{|env| [200, {'Content-Type' => 'text/html', 'Cache-Control' => 'public'}, ['one']]}
    @cache.should.equal({'/path/to/blah.html' => ['one']})
  end
  
  specify 'should cache requests when including "public" cache control directives' do
    request{|env| [200, {'Content-Type' => 'text/html', 'Cache-Control' => 'max-age=300, public'}, ['many']]}    
    @cache.should.equal({'/path/to/blah.html' => ['many']})
  end
  
  specify 'should cache when no cache control directives' do
    request{|env| [200, {'Content-Type' => 'text/html'}, ['none']]}
    @cache.should.equal({'/path/to/blah.html' => ['none']})
  end

  specify "should not cache results if the block returns nil or false" do
    request(:rc_block => proc{false})
    @cache.should.equal({})
    request(:rc_block => proc{nil})
    @cache.should.equal({})
  end

  specify "should cache results to path returned by block" do
    request(:rc_block => proc{"1"})
    @cache.should.equal("1" => @def_value)
    request(:rc_block => proc{"2"})
    @cache.should.equal("1" => @def_value, "2" => @def_value)
  end

  specify "should pass the environment and response to the block" do
    e, r = nil, nil
    request(:rc_block => proc{|env,res| e, r = env, res; nil})
    e['PATH_INFO'].should.equal @def_path
    e['REQUEST_METHOD'].should.equal 'GET'
    e['QUERY_STRING'].should.equal ''
    r.should.equal([200, {"Content-Type" => "text/html"}, ["rack-response-cache"]])
  end

  specify "should unescape the path by default" do
    request(:path => '/path%20with%20spaces')
    @cache.should.equal('/path with spaces.html' => @def_value)
    request(:path => '/path%3chref%3e')
    @cache.should.equal('/path with spaces.html' => @def_value, '/path<href>.html' => @def_value)
  end

  specify "should cache html mime_type without extension at .html" do
    request(:path => '/a')
    @cache.should.equal('/a.html' => @def_value)
  end

  {
    :css => %w[text/css],
    :csv => %w[text/csv],
    :html => %w[text/html],
    :js => %w[text/javascript application/javascript],
    :pdf => %w[application/pdf],
    :txt => %w[text/plain],
    :xhtml => %w[application/xhtml+xml],
    :xml => %w[text/xml],
  }.each do |extension, mime_types|
    mime_types.each do |mime_type|
      specify "should cache #{mime_type} responses with the extension ('#{extension}') unchanged" do
        request(:path => "/a.#{extension}", :headers => {'CT' => mime_type})
        @cache.should.equal("/a.#{extension}" => @def_value)
      end

      specify "should cache #{mime_type} responses with the relevant extension ('#{extension}') added if not already present" do
        request(:path => '/a', :headers => {'CT' => mime_type})
        @cache.should.equal("/a.#{extension}" => @def_value)
      end
    end
  end
  
  specify "should cache 'text/html' responses with the extension ('htm') unchanged" do
    request(:path => "/a.htm", :headers => {'CT' => "text/html"})
    @cache.should.equal("/a.htm" => @def_value)
  end
  
  [:css, :xml, :xhtml, :js, :txt, :pdf, :csv].each do |extension|
    specify "should not cache if extension and content-type don't agree" do
      request(:path => "/d.#{extension}", :headers => {'CT' => 'text/html'})
      @cache.should.equal({})
    end    
  end

  specify "should cache text/html responses with empty basename to index.html" do
    request(:path => '/',        :headers => {'CT' => "text/html"})
    request(:path => '/blah/',   :headers => {'CT' => "text/html"})
    request(:path => '/blah/2/', :headers => {'CT' => "text/html"})
    @cache.should.equal("/index.html"        => @def_value,
                        "/blah/index.html"   => @def_value,
                        "/blah/2/index.html" => @def_value)
  end
  
  specify "should not cache non-text/html responses with empty basename" do
    request(:path => '/',        :headers => {'CT' => "text/csv"})
    request(:path => '/blah/',   :headers => {'CT' => "text/css"})
    request(:path => '/blah/2/', :headers => {'CT' => "text/plain"})
    @cache.should.equal({})
  end
  
  specify "should cache unrecognized extensions with text/html content-type at .html" do
    request(:path => "/a.seo", :headers => {'CT' => "text/html"})
    @cache.should.equal("/a.seo.html" => @def_value)
  end

  specify "should not cache unrecognized content-types" do
    request(:path => "/a", :headers => {'CT' => "text/unrecognised"})
    @cache.should.equal({})
  end

  specify "should recognize content-types with supplied parameters (eg. charset)" do
    request(:path => "/a", :headers => {'CT' => "text/html; charset=utf-8"})
    @cache.should.equal("/a.html" => @def_value)
  end

  specify "should raise an error if a cache argument is not provided" do
    app = Rack::Builder.new{use Rack::ResponseCache; run lambda { |env| [200, {'Content-Type' => 'text/plain'}, Rack::Request.new(env).POST]}}
    proc{Rack::MockRequest.new(app).get('/')}.should.raise(ArgumentError)
  end

end
