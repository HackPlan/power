# Where the magic happens.
#
# Pow's `HttpServer` runs as your user and listens on a high port
# (20559 by default) for HTTP requests. (An `ipfw` rule forwards
# incoming requests on port 80 to your Pow instance.) Requests work
# their way through a middleware stack and are served to your browser
# as static assets, Rack requests, or error pages.

fs              = require "fs"
url             = require "url"
connect         = require "connect"
harp            = require "harp"
request         = require "request"

{pause} = require "./util"
{dirname, join} = require "path"

{version} = JSON.parse fs.readFileSync __dirname + "/../package.json", "utf8"

# `HttpServer` is a subclass of
# [Connect](http://senchalabs.github.com/connect/)'s `HTTPServer` with
# a custom set of middleware and a reference to a Pow `Configuration`.
module.exports = class HttpServer extends connect.HTTPServer

  # Connect depends on Function.prototype.length to determine
  # whether a given middleware is an error handler. These wrappers
  # provide compatibility with bound instance methods.
  o = (fn) -> (req, res, next)      -> fn req, res, next
  x = (fn) -> (err, req, res, next) -> fn err, req, res, next

  # Helper that loads the named template, creates a new context from
  # the given context with itself and an optional `yieldContents`
  # block, and passes that to the template for rendering.
  renderTemplate = (templateName, renderContext, yieldContents) ->
    template = require "./templates/http_server/#{templateName}.html"
    context = {renderTemplate, yieldContents}
    context[key] = value for key, value of renderContext
    template context

  # Helper to render `templateName` to the given `res` response with
  # the given `status` code and `context` values.
  renderResponse = (res, status, templateName, context = {}) ->
    res.writeHead status, "Content-Type": "text/html; charset=utf8", "X-Power-Template": templateName
    res.end renderTemplate templateName, context

  # Create an HTTP server for the given configuration. This sets up
  # the middleware stack, gets a `Logger` instace for the global
  # access log, and registers a handler to close any running
  # applications when the server shuts down.
  constructor: (@configuration) ->
    super [
      o @logRequest
      o @annotateRequest
      o @handlePowerRequest
      o @findHostConfiguration
      o @handleStaticRequest
      o @handleProxyRequest
      o @handleApplicationNotFound
      o @handleWelcomeRequest
      o @handleLocationNotFound
    ]

    @staticHandlers = {}
    @requestCount = 0

    @accessLog = @configuration.getLogger "access"

  # Gets an object describing the server's current status that can be
  # passed to `JSON.stringify`.
  toJSON: ->
    pid: process.pid
    version: version
    requestCount: @requestCount

  # The first middleware in the stack logs each incoming request's
  # source address, method, hostname, and path to the access log
  # (`~/Library/Logs/Pow/access.log` by default).
  logRequest: (req, res, next) =>
    @accessLog.info "[#{req.socket.remoteAddress}] #{req.method} #{req.headers.host} #{req.url}"
    @requestCount++
    next()

  # Annotate the request object with a `pow` property whose value is
  # an object that will hold the request's normalized hostname, root
  # path, and application, if any. (Only the `pow.host` property is
  # set here.)
  annotateRequest: (req, res, next) ->
    host = req.headers.host?.replace /(\.$)|(\.?:.*)/, ""
    req.power = {host}
    next()

  # Serve requests for status information at `http://power/`. The status
  # endpoints are:
  #
  # * `/config.json`: Returns a JSON representation of the server's
  #   `Configuration` instance.
  # * `/env.json`: Returns the environment variables that all spawned
  #   applications inherit.
  # * `/status.json`: Returns information about the current server
  #   version, number of requests handled, and process ID.
  #
  # Third-party utilities may use these endpoints to inspect a running
  # Pow server.
  handlePowerRequest: (req, res, next) =>
    return next() unless req.power.host is "power"

    switch req.url
      when "/config.json"
        res.writeHead 200
        res.end JSON.stringify @configuration
      when "/env.json"
        res.writeHead 200
        res.end JSON.stringify @configuration.env
      when "/status.json"
        res.writeHead 200
        res.end JSON.stringify this
      else
        @handleLocationNotFound req, res, next

  # After the request has been annotated, attempt to match its hostname
  # using the server's configuration. If a host configuration is found,
  # annotate the request object with the application's root path or the
  # port number so we can use it further down the stack.
  findHostConfiguration: (req, res, next) =>
    resume = pause req

    @configuration.findHostConfiguration req.power.host, (err, domain, config) =>
      if config
        req.power.root   = config.root if config.root
        req.power.url    = config.url  if config.url
        req.power.domain = domain
        req.power.resume = resume
      else
        resume()
      next err

  # If this is a `GET` or `HEAD` request matching a file in the
  # application's `public/` directory, serve the file directly.
  handleStaticRequest: (req, res, next) =>
    unless req.method in ["GET", "HEAD"]
      return next()

    unless (root = req.power.root) and typeof root is "string"
      return next()

    if req.url.match /\.\./
      return next()

    handler = @staticHandlers[root] ?= harp.mount(root)
    handler req, res, next

  # If the request object is annotated with a url, proxy the
  # request off to the hostname and port.
  handleProxyRequest: (req, res, next) =>
    return next() unless req.power.url
    {hostname, port} = url.parse req.power.url

    headers = {}

    for key, value of req.headers
      headers[key] = value

    headers['X-Forwarded-For']    = req.connection.address().address
    headers['X-Forwarded-Host']   = req.power.host
    headers['X-Forwarded-Server'] = req.power.host

    proxy = request
      method: req.method
      url: "#{req.power.url}#{req.url}"
      headers: headers
      jar: false
      followRedirect: false

    req.pipe proxy
    proxy.pipe res

    proxy.on 'error', (err) ->
      renderResponse res, 500, "proxy_error",
        {err, hostname, port}

    req.power.resume()

  # Show a friendly message when accessing a hostname that hasn't been
  # set up with Power yet (but only for hosts that the server is
  # configured to handle).
  handleApplicationNotFound: (req, res, next) =>
    return next() if req.power.root

    host = req.power.host
    pattern = @configuration.httpDomainPattern
    return next() unless domain = host?.match(pattern)?[1]

    name = host.slice 0, host.length - domain.length
    return next() unless name.length

    renderResponse res, 503, "application_not_found", {name, host}

  # If the request is for `/` on an unsupported domain (like
  # `http://localhost/` or `http://127.0.0.1/`), show a page
  # confirming that Power is installed and running, with instructions on
  # how to set up an app.
  handleWelcomeRequest: (req, res, next) =>
    return next() if req.power.root or req.url isnt "/"
    {domains} = @configuration
    domain = if "dev" in domains then "dev" else domains[0]
    renderResponse res, 200, "welcome", {version, domain}

  # If the request ends up here, it's for a static site, but the
  # requested file doesn't exist. Show a basic 404 message.
  handleLocationNotFound: (req, res, next) ->
    res.writeHead 404, "Content-Type": "text/html"
    res.end "<!doctype html><html><body><h1>404 Not Found</h1>"