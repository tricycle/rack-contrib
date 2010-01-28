require 'fileutils'
require 'rack'

# Rack::ResponseCache is a Rack middleware that caches responses for successful
# GET requests with no query string to disk or any ruby object that has an
# []= method (so it works with memcached).  When caching to disk, it works similar to
# Rails' page caching, allowing you to cache dynamic pages to static files that can
# be served directly by a front end webserver.
class Rack::ResponseCache
  CONTENT_TYPES = {
    "application/pdf" => %w[pdf],
    "application/xhtml+xml" => %w[xhtml],
    "text/css" => %w[css],
    "text/csv" => %w[csv],
    "text/html" => %w[html htm],
    "text/javascript" => %w[js], "application/javascript" => %w[js],
    "text/plain" => %w[txt],
    "text/xml" => %w[xml],
    "text/x-component" => %w[htc],
  }
  ALLOWED_EXTENSIONS = CONTENT_TYPES.values.flatten.uniq

  # The default proc used if a block is not provided to .new
  # Doesn't cache unless path does not contain '..', Content-Type is
  # whitelisted, and path agrees with Content-Type
  # Inserts appropriate extension if no extension in path
  # Uses /index.html if path ends in /
  DEFAULT_PATH_PROC = proc do |env, res|
    path = Rack::Utils.unescape(env['PATH_INFO'])
    
    content_type = res[1]['Content-Type'].to_s.split(';').first
    extension = File.extname(path)[1..-1]
    
    if !path.include?('..') and (allowed_extensions_for_content_type = CONTENT_TYPES[content_type])
      # path doesn't include '..' and Content-Type is whitelisted
      case
      when path.match(/\/$/) && content_type == "text/html"
        # path ends in / and Content-Type is text/html
        path << "index.html"
      when path.match(/\/$/) && content_type != "text/html"
        # path ends in / and Content-Type is not text/html - don't cache
        path = nil
      when File.extname(path) == "" ||
        (!ALLOWED_EXTENSIONS.include?(extension) && content_type == "text/html")
        # no extension OR
        # unrecognized extension AND content_type is text/html
        path << ".#{allowed_extensions_for_content_type.first}"
      when !allowed_extensions_for_content_type.include?(extension)
        # extension doesn't agree with Content-Type (but extension is recognized) - don't cache
        path = nil
      else
        # do nothing, path is alright
      end
    else
      # don't cache
      path = nil
    end
    
    path
  end

  # Initialize a new ReponseCache object with the given arguments.  Arguments:
  # * app : The next middleware in the chain.  This is always called.
  # * cache : The place to cache responses.  If a string is provided, a disk
  #   cache is used, and all cached files will use this directory as the root directory.
  #   If anything other than a string is provided, it should respond to []=, which will
  #   be called with a path string and a body value (the 3rd element of the response).
  # * &block : If provided, it is called with the environment and the response from the next middleware.
  #   It should return nil or false if the path should not be cached, and should return
  #   the pathname to use as a string if the result should be cached.
  #   If not provided, the DEFAULT_PATH_PROC is used.
  def initialize(app, cache, &block)
    @app = app
    @cache = cache
    @path_proc = block || DEFAULT_PATH_PROC
  end

  # Call the next middleware with the environment.  If the request was successful (response status 200),
  # was a GET request, did not have a 'no-cache' cache control directive and had an empty query string, 
  # call the block set up in initialize to get the path. 
  # If the cache is a string, create any necessary middle directories, and cache the file in the appropriate
  # subdirectory of cache.  Otherwise, cache the body of the reponse as the value with the path as the key.
  def call(env)
    @env = env
    @res = @app.call(@env)
    if cacheable? and path = @path_proc.call(@env, @res)
      if @cache.is_a?(String)
        path = File.join(@cache, path) if @cache
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'wb'){|f| @res[2].each{|c| f.write(c)}}
      else
        @cache[path] = @res[2]
      end
    end
    @res
  end
  
  private 
  def cacheable?
    get and !query_string and success and !no_cache and !private_cache
  end
  
  def get
    @env['REQUEST_METHOD'] == 'GET'
  end
  
  def query_string
    @env['QUERY_STRING'] != ''
  end
  
  def success
    @res[0] == 200
  end
  
  def private_cache
    cache_control_directives.include? 'private'
  end
  
  def no_cache
    cache_control_directives.include? 'no-cache'
  end
  
  def cache_control_directives
    (@res[1]["Cache-Control"] || "").split(',').collect {|d| d.strip}
  end
end
