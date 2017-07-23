path = require 'path'
qs = require 'qs'


init_express = ( app, ctx={} ) ->

  app.set 'env', ctx.envname
  if process.env.SITEFILE_PORT
    ctx.site.port = process.env.SITEFILE_PORT

  app.set 'port', ctx.site.port
  app.set 'showStackError', ctx.config['show-stack-trace']

  #app.use express.static path.join ctx.noderoot, 'public'

  engines = require 'consolidate'
  app.engine 'pug', engines.pug
  #app.engine 'handlebars', engines.handlebars

  # Use middleware, configuring modules from Sitefile
  for mw in ctx.middleware
    app.use mw.passthrough


parse_simple_types = ( query ) ->

  for key, value of query
    if value in [ 'true', 'false' ]
      query[key] = Boolean value
    else if not isNaN parseInt value, 10
      query[key] = parseInt value, 10
    else if typeof value == "object"
      parse_simple_types query[key]
        

module.exports =
  init: init_express
  query_parser: ( query_str ) ->
    query = qs.parse query_str
    parse_simple_types query
    query

