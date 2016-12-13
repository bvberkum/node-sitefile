fs = require 'fs'
path = require 'path'
cc = require 'coffee-script'
_ = require 'lodash'


pm2_app_defaults = ( obj ) ->
  _.defaultsDeep obj, {
    name: null
    pid: null
    pm_id: null
    pm2_env:
      status: null
      cwd: null
      pm_uptime: null
      pm_exec_path: null
      ENV: null
    versioning: {}
  }

class PM2Config
  constructor: ( @cwd ) ->
    @pm2_config = []
    @pm2_config_dir = null
    @pm2_config_file = null
  load: ( filename ) ->
    @pm2_config_file = filename
    if path.dirname(filename) != filename
      @pm2_config_dir = path.join @cwd, path.dirname filename
      if not fs.existsSync @pm2_config_dir
        throw new Exception "Directory should exist: #{filename}"
    @pm2_config_file = path.join @cwd, filename
    if fs.existsSync @pm2_config_file
      @pm2_config = require(@pm2_config_file).apps
      for pm2_proc in @pm2_config
        pm2_app_defaults pm2_proc

class PM2Dump
  constructor: ( @cwd ) ->
    @pm2_dump = []
    @pm2_dump_dir = null
    @pm2_dump_file = null
  load: ( filename ) ->
    @pm2_dump_file = filename
    @pm2_dump_file = path.join @cwd, filename
    if not fs.existsSync @pm2_dump_file
      throw new Exception "No such file #{filename}"
    @pm2_dump = require(@pm2_dump_file)

class PM2Manager
  constructor: ( @cwd ) ->
    @procs = []
  add: ( pm2_proc ) ->
    pm2_app_defaults pm2_proc
    @procs.push pm2_proc
  save: ->
  load: ( filename )->
    cfg = new PM2Config @cwd
    cfg.load filename
    @procs = cfg.pm2_config
  get_by_id: ( app_id) ->
    for app in @procs
      if app.pm_id == app_id
        return app
  get_by_name: ( app_name ) ->
    for app in @procs
      if app.name == app_name
        return app
  update_by_name: ( app ) ->
    for pm2_proc in @procs
      if app.name == pm2_proc.name
        _.merge pm2_proc, app
  name_exists: ( app_name ) ->
    for app in @procs
      if app.name == app_name
        return true
    return false


module.exports = ( ctx ) ->

  try
    pm2 = require 'pm2'
  catch
    return

  httprouter = require('./http') ctx
  pugrouter = require('./pug') ctx
  
  detailPugFn = path.join( __dirname, 'pm2/view/detail.pug' )

  listPugFn = path.join( __dirname, 'pm2/view/list.pug' )
  listCoffeeFn = path.join( __dirname, 'pm2/view/list.coffee' )

  name: 'pm2'

  #route:
  #    pm2/: 'redir:pm2.html'

  generate:
    default: ( rctx ) ->

      console.log 'PM2', ctx.site.base, rctx.name, rctx.res, rctx.route
      if not rctx.res.path
        throw Error "JSON path expected (#{rctx.route.handler})"

      data = require path.join '../../..', rctx.res.path

      null

    ps: ( rctx ) ->

      m = new PM2Manager ctx.cwd
      # If given, use spec for JSON config file
      if rctx.route.spec and rctx.route.spec != '#'
        m.load rctx.route.spec

      pm2.list (err, ps_list) ->
        for app in ps_list
          if m.name_exists app.name
            m.update_by_name app
          else
            m.add app

      # List all PM2 procs in JSON
      ctx.app.get ctx.site.base+rctx.name+'.json', (req, res) ->
        #pm2.list (err, ps_list) ->
        res.type 'json'
        #if err
        #  res.status 500
        res.write JSON.stringify m.procs
        res.end()

      # Describe single PM2 proc in JSON
      ctx.app.get ctx.site.base+rctx.name+'/:pm_id.json', (req, res) ->
        pm2.describe req.params.pm_id, (err, ps_list) ->
          res.type 'json'
          if err
            res.status 500
          res.write JSON.stringify ps_list[0]
          res.end()

      ctx.app.post ctx.site.base+rctx.name+'/:pm_id/start', (req, res) ->
        console.log 'start', req.params.pm_id
        pm2_proc = m.get_by_id parseInt req.params.pm_id, 10
        console.log 'start', pm2_proc.name, pm2_proc
        pm2.start pm2_proc, ( err ) ->
          res.type 'txt'
          if err
            res.status 500
            res.write err
          res.end()

      ctx.app.post ctx.site.base+rctx.name+'/:pm_id/restart', (req, res) ->
        pm2.gracefulReload req.params.pm_id, ( err ) ->
          res.type 'txt'
          if err
            res.status 500
            res.write err
          res.end()

      ctx.app.post ctx.site.base+rctx.name+'/:pm_id/stop', (req, res) ->
        pm2.stop req.params.pm_id, ( err ) ->
          res.type 'txt'
          if err
            res.status 500
            res.write err
          res.end()


      # Serve PM2 proc HTML details
      ctx.app.get ctx.site.base+rctx.name+'/:pm_id.html', (req, res) ->

        console.log req.path.substring(0, req.path.length - 5) + '.json'
        httprouter.promise.json(
          hostname: 'localhost'
          port: ctx.app.get('port')
          path: req.path.substring(0, req.path.length - 5) + '.json'
        ).then ( app ) ->

          res.type 'html'
          res.write pugrouter.compile detailPugFn, {
            compile: rctx.route.options.compile
            merge:
              pid: process.pid
              base: ctx.site.base+rctx.name
              script: ctx.site.base+rctx.name+'.js'
              options: rctx.route.options
              query: req.query
              context: rctx
              app: app
          }
          res.end()


      # Serve HTML list view
      ctx.app.get ctx.site.base+rctx.name+'.html', (req, res) ->

        httprouter.promise.json(
          hostname: 'localhost'
          port: ctx.app.get('port')
          path: ctx.site.base + rctx.name + '.json'
        ).then ( apps ) ->

          res.type 'html'
          res.write pugrouter.compile listPugFn, {
            compile: rctx.route.options.compile
            merge:
              pid: process.pid
              pm2_base: ctx.site.base+rctx.name
              script: ctx.site.base+rctx.name+'.js'
              options: rctx.options
              query: req.query
              context: rctx
              apps: apps
          }
          res.end()


      # Serve JS for list-view
      ctx.app.get ctx.site.base+rctx.name+'.js', (req, res) ->
        res.type 'js'
        res.write cc._compileFile listCoffeeFn
        res.end()


      ctx.app.get ctx.site.base+rctx.name+'/', (req, res) ->
        res.redirect ctx.site.base+rctx.name+'.html'

      # FIXME: return routes so Sitefile can set dir defaults
      dir = path.dirname(ctx.site.base+rctx.name)
      if dir not of ctx.routes.directories
        ctx.routes.directories[ dir ] = []
      ctx.routes.directories[ dir ].push path.basename rctx.name

      #route:
      #  directories:
      #    ctx.site.base+rctx.name+'/':
          
      null

