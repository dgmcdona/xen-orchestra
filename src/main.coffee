# File system handling.
$fs = require 'fs'

#---------------------------------------------------------------------

# Low level tools.
$_ = require 'underscore'

# HTTP(s) middleware framework.
$connect = require 'connect'

# Configuration handling.
$nconf = require 'nconf'

# WebSocket server.
$WSServer = (require 'ws').Server

# YAML formatting and parsing.
$YAML = require 'js-yaml'

#---------------------------------------------------------------------

$API = require './api'
$Session = require './session'
$XO = require './xo'

# Helpers for dealing with fibers.
{$fiberize, $synchronize} = require './fibers-utils'

# HTTP/HTTPS server which can listen on multiple ports.
$WebServer = require './web-server'

#=====================================================================

$handleJsonRpcCall = (api, session, encodedRequest) ->
  request = {
    id: null
  }

  formatError = (error) -> JSON.stringify {
    jsonrpc: '2.0'
    error: error
    id: request.id
  }

  # Parses the JSON.
  try
    request = JSON.parse encodedRequest.toString()
  catch error
    return formatError (
      if error instanceof SyntaxError
        $API.err.INVALID_JSON
      else
        $API.err.SERVER_ERROR
    )

  # Checks it is a compliant JSON-RPC 2.0 request.
  if not request.method or not request.params or request.id is undefined or request.jsonrpc isnt '2.0'
    return formatError $API.err.INVALID_REQUEST

  # Executes the requested method on the API.
  exec = $synchronize 'exec', api
  try
    JSON.stringify {
      jsonrpc: '2.0'
      result: exec session, request
      id: request.id
    }
  catch error
    # If it is not a valid API error, hides it with a generic server error.
    unless ($_.isObject error) and (error not instanceof Error)
      error = $API.err.SERVER_ERROR

    formatError error

#=====================================================================

# Main.
do $fiberize ->

  # Loads the environment.
  $nconf.env()

  # Parses process' arguments.
  $nconf.argv()

  # Loads the configuration file.
  $nconf.use 'file', {
    file: "#{__dirname}/../config/local.yaml"
    format: {
      stringify: (obj) -> $YAML.safeDump obj
      parse: (string) -> $YAML.safeLoad string
    }
  }

  # Defines defaults configuration.
  $nconf.defaults {
    http: {
      listen: [
        port: 80
      ]
      mounts: []
    }
    redis: {
      # Default values are handled by `redis`.
    }
  }

  # Prints a message if deprecated entries are specified.
  for entry in ['users', 'servers']
    if $nconf.get entry
      console.warn "[Warn] `#{entry}` configuration is deprecated."

  # Creates the main object which will connects to Xen servers and
  # manages all the models.
  xo = new $XO()

  # Starts it.
  xo.start {
    redis: {
      uri: $nconf.get 'redis:uri'
    }
  }

  # Creates the web server according to the configuration.
  webServer = new $WebServer()
  webServer.listen options for options in $nconf.get 'http:listen'

  # Static file serving (e.g. for XO-Web).
  connect = $connect()
  for urlPath, filePaths of $nconf.get 'http:mounts'
    filePaths = [filePaths] unless $_.isArray filePaths
    for filePath in filePaths
      connect.use urlPath, $connect.static filePath
  webServer.on 'request', connect

  # Creates the API.
  api = new $API xo

  # # JSON-RPC over WebSocket.
  new $WSServer({
    server: webServer
    path: '/api/'
  }).on 'connection', (socket) ->
    # Binds a session to this connection.
    session = new $Session xo
    session.once 'close', -> socket.close()
    socket.once 'close', -> session.close()

    # Handles each request in a separate fiber.
    socket.on 'message', $fiberize (request) ->
      response = $handleJsonRpcCall api, session, request

      # The socket may have closed beetween the request and the
      # response.
      socket.send response if socket.readyState is socket.OPEN
