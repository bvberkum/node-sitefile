fs = require 'fs'
path = require 'path'
glob = require 'glob'
yaml = require 'js-yaml'
_ = require 'lodash'
chalk = require 'chalk'
semver = require 'semver'
Context = require '../context'


libconf = require '../conf'

version = '0.0.3'

c =
  sc: chalk.grey ':'


String::startsWith ?= (s) -> @[...s.length] is s
String::endsWith   ?= (s) -> s is '' or @[-s.length..] is s


builtin = [ 'redir', 'static' ]


get_local_sitefile_name = ( ctx={} ) ->
  fn = null
  ext = null
  _.defaults ctx, basename: 'Sitefile', exts: [
    '.json'
    '.yml'
    '.yaml'
  ]
  for ext in ctx.exts
    fn = ctx.basename + ext
    if fs.existsSync fn
      ctx.fn = fn
      ctx.ext = ext
      break
    fn = null
  if not fn
    throw new Error "No #{ctx.basename}"
  ctx.lfn = path.join process.cwd(), fn
  ctx.lfn


get_local_sitefile = ( ctx={} ) ->
  lfn = get_local_sitefile_name ctx
  sitefile = libconf.load_file lfn

  if not semver.satisfies sitefile.sitefile, '<='+ctx.version
    throw new Error "Version #{ctx.version} does not satisfy "+
        "sitefile #{sitefile.sitefile}"
  # TODO: validate Sitefile schema

  sitefile.path = path.relative process.cwd(), lfn

  _.defaults sitefile,
    routes: {}
    specs: {}

  sitefile


load_sitefile = ( ctx ) ->
  ctx.sitefile = get_local_sitefile ctx
  log "Loaded", path: path.relative ctx.cwd, ctx.lfn

  # translate JSON path refs in sitefile to use global sitefile context
  # ie. prefix path with sitefile
  xform = (result, value, key) ->
    if _.isArray value
      for item, index in value
        xform value, item, index
    else if _.isObject value
      if value.$ref
        value.$ref = '#/sitefile' + value.$ref.substr(1)
      else
        for key, property of value
          xform value, property, key
      result[ key ] = value

  _.transform ctx.sitefile, xform


load_rc = ( ctx ) ->
  ctx.static = libconf.load 'sitefilerc', suffixes: [ '' ], all: true
  ctx.static


load_config = ( ctx={} ) ->
  if not ctx.config_name?
    ctx.config_name = 'config/config'
    # XXX config per client
    #scriptconfig = 'config/config-#{ctx.proc.name}'
    #configs = glob.sync path.join ctx.noderoot, scriptconfig + '.*'
    #if not _.isEmpty configs
    #  ctx.config_name = scriptconfig
  ctx.config_envs = require path.join ctx.noderoot, ctx.config_name
  ctx.config = ctx.config_envs[ctx.envname]
  ctx.config


prepare_context = ( ctx={} ) ->

  # Apply all static properties (set ctx.static too)
  _.merge ctx, load_rc ctx

  # Appl defaults if not present
  _.defaults ctx,
    noderoot: path.dirname path.dirname __dirname
    version: version
    routers: {}
    cwd: process.cwd()
    proc:
      name: path.basename process.argv[1]
    envname: process.env.NODE_ENV or 'development'
  _.defaults ctx,
    pkg_file: path.join ctx.noderoot, 'package.json'
  _.defaults ctx,
    pkg: require( ctx.pkg_file )

  if not ctx.config
    load_config ctx

  # Load local sitefile (set ctx.sitefile)
  if not ctx.sitefile?
    load_sitefile ctx

  new Context ctx


# Express redir handler
redir = ( app, ref, p ) ->
  app.all ref, (req, res) ->
    res.redirect p


# Split sitefile router specs
parse_spec = ( strspec, ctx={} ) ->
  [ handler_path, hspec ] = strspec.split(':')
  if handler_path.indexOf '.' != -1
    [ router_name, handler_name ] = handler_path.split '.'
  else
    router_name = handler_path
  [ router_name, handler_name, hspec ]


# return generator for express route-handlers
get_handler_gen = ( router_name, ctx={} ) ->
  # add generated routes, track dirs/leafs
  if router_name not in _.keys ctx.routers
    throw new Error "No such router: #{router_name}"
  router = ctx.routers[ router_name ].object
  # return route-handler generator
  router.generate


# load routers and parameters onto context
load_routers = ( ctx ) ->

  if _.isEmpty ctx.sitefile.routes
    return

  _.defaults ctx, router_names: [], routers: {}

  if _.isEmpty ctx.router_names
    # parse sitefile.routes, pass 1: load & init routers
    ctx.router_names = _.union (
      router_name for [ router_name, handler_name, handler_spec ] in (
        parse_spec strspec, ctx for route, strspec of ctx.sitefile.routes ) )

  log 'Required routers', name: ctx.router_names.join ', '

  # import handler generators
  for name in ctx.router_names
    if name in builtin
      continue
    router_cb = require './routers/' + name
    router_obj = router_cb ctx

    if not router_obj
      warn "Failed to load #{name}"
      continue

    ctx.routers[name] = module: router_cb, object: router_obj
    log "Loaded router", name: name, c.sc, router_obj.label


# For each given dir-name: leafs pair,
# add a redir rule to redirect to a dir leaf
add_dir_redirs = ( dirs, app, ctx ) ->
  # Add redirections for dirs to default leafs
  for url, leafs of dirs
    if leafs.length == 1
      defleaf = leafs[0]
    if leafs
      for name in ctx.dir.defaults
        if name in leafs
          defleaf = name
          break
      if not defleaf
        warn "Cannot choose default dir index for #{url}"
        continue
      redir app, url, url+'/'+defleaf
      log "Dir", url: "#{url}/{->#{defleaf}}"



# Apply routes in sitefile to Express
apply_routes = ( sitefile, app, ctx={} ) ->

  _.defaults ctx, base: '/',
    dir: defaults: [ 'default', 'index', 'main' ]

  if not _.isEmpty sitefile.routes

    # Track all dirs for generated files
    # TODO May want the same for regular routes.
    # TODO Also need to refactor, and scan for defaults across dirs rootward
    dirs = {}

    # parse sitefile.routes, pass 2: process specs to handler intances
    for route, strspec of sitefile.routes

      [ router_name, handler_name, handler_spec ] = parse_spec strspec, ctx

      if router_name not in builtin and not ctx.routers[ router_name ]

        log "Skipping route", name: router_name, c.sc, path: handler_spec
        continue

      if route.startsWith '$'

        handler = get_handler_gen router_name, ctx

        log 'Dynamic', url: route, id: router_name, path: handler_spec

        for name in glob.sync handler_spec
          extname = path.extname name
          basename = path.basename name, extname
          dirname = path.dirname name
          if dirname == '.'
            url = '/' + basename # FIXME route.replace('$name')
          else
            url = "/#{dirname}/#{basename}" # FIXME route.replace('$name')
            if not dirs.hasOwnProperty '/' + dirname
              dirs[ '/'+dirname ] = [ basename ]
            else
              dirs[ '/'+dirname ].push basename

          log route, url: url, '=', path: name
          redir app, url+extname, url
          app.all url, handler '.'+url, ctx

      else
        # add route for single resource or redirection
        url = ctx.base + route

        # static and redir are built-in
        if router_name == 'redir'
          p = '/'+strspec.substr 6
          redir app, url, p
          log '     *', url: url, '->', url: p

        else if router_name == 'static'
          p = path.join ctx.cwd, handler_spec
          app.use url, ctx.static_proto p
          log 'Static', url: url, '=', path: p

        else
          # use router to generate handler for resource
          handler = get_handler_gen router_name, ctx
          log "Express All", id: router_name, path: handler_spec
          app.all url, handler handler_spec, ctx

    # redirect dirs to default dir-index resource
    add_dir_redirs dirs, app, ctx

  else
    warn 'No routes'
    process.exit()


expand_globs = ( patterns ) ->
  _.flattenDeep [ glob.sync p for p, i in patterns ]


# XXX only reloads on src file or sitefile change
# XXX does not reload routes, code+config only
# TODO should reload sitefilerc, should reset/apply routes
reload_on_change = ( app, ctx ) ->
  config_watch = ctx.noderoot + '/config/**/*'
  paths = expand_globs [ config_watch ]
  log 'Watching configs', path: paths.join ', '
  for fn in paths
    fs.watchFile fn, ( cur, prev ) ->
      log "Reloading config", "because: #{fn} changed"
      load_config ctx

  log 'Watching sitefile', path: ctx.lfn
  fs.watchFile ctx.lfn, ( cur, prev ) ->
    log "Reloading context", "because: #{ctx.lfn} changed"
    load_sitefile ctx
    log "", id: ctx.sitefile.specs


warn = ->
  v = Array.prototype.slice.call( arguments )
  out = [ chalk.red(v.shift()) + c.sc ]
  console.warn.apply null, log_line( v, out )

log = ->
  v = Array.prototype.slice.call( arguments )
  header = _.padLeft v.shift(), 21
  out = [ chalk.blue(header) + c.sc ]
  console.log.apply null, log_line( v, out )

log_line = ( v, out=[] ) ->
  while v.length
    o = v.shift()
    if _.isString o
      if o.match /^[\<\>_:-]+$/
        out.push chalk.grey o
      else if o.match /[\<\>=_]+/
        out.push chalk.magenta o
      else
        out.push o
    else if o.path
      out.push chalk.green o.path
    else if o.url
      out.push chalk.yellow o.url
    else if o.name
      out.push chalk.cyan o.name
    else if o.id
      out.push chalk.magenta o.id
    else
      throw new Error "log: unhandled " + JSON.stringify o
  out


module.exports = {
  version: version
  get_local_sitefile_name: get_local_sitefile_name
  get_local_sitefile: get_local_sitefile
  prepare_context: prepare_context
  load_config: load_config
  apply_routes: apply_routes
  reload_on_change: reload_on_change
  load_routers: load_routers
  load_rc: load_rc
  log: log
}

