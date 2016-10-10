#!/usr/bin/env coffee

lib = require '../lib/sitefile'
_ = require 'lodash'



# export server
module.exports =

  # read-only public vars
  port: null
  host: null
  proc: null

  run: ( done ) ->

    # prepare context and config data, loads sitefile
    ctx = lib.prepare_context ctx
    if _.isEmpty ctx.sitefile.routes
      lib.warn 'No routes'
      process.exit()

    # initialize Express
    express_handler = require '../lib/sitefile/express'
    ctx.app = express_handler ctx
  
    # further Express setup using sitefile
    sf = new lib.Sitefile ctx

    # serve forever
    console.log "Starting server at localhost:#{ctx.port}"
    if ctx.host
      proc = ctx.server.listen ctx.port, ctx.host, ->
        lib.log "Listening", "Express server on port #{ctx.port}. "
    else
      proc = ctx.server.listen ctx.port, ->
        lib.log "Listening", "Express server on port #{ctx.port}. "

    module.exports.host = ctx.host
    module.exports.port = ctx.port
    module.exports.proc = proc
    !done || done()
    proc


# start if directly executed
if process.argv.join(' ') == 'coffee '+require.resolve './sitefile.coffee'

  module.exports.run()

else if process.argv[2] in [ '--version', '--help' ]
 
  console.log "sitefile/"+lib.version

# TODO: detect execute or (test-mode) include
#else
#  lib.warn "Invalid argument:", process.argv[2]
#  process.exit(1)


# Id: node-sitefile/0.0.4-dev-fdata bin/sitefile.coffee
# vim:ft=coffee:
