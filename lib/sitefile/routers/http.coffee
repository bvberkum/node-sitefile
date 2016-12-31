
_ = require 'lodash'
http = require 'http'
path = require 'path'
fs = require 'fs'
URL = require 'url'

Router = require '../Router'

Promise = require 'bluebird'


clientAcc = \
  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'

promise_resource = ( { url, accType = null, reqType, opts = {} } ) ->

  if not accType and not reqType
    reqType = 'application/json'
  if not opts.headers
    opts.headers = {
      "Accept-Type": accType or reqType
    }
  if url
    opts.url = url

  #= 'application/json'
  new Promise (resolve, reject) ->
    http
      .get opts, ( res ) ->
        statusCode = res.statusCode
        contentType = res.headers['content-type']
        error = null
        if statusCode != 200
          error = new Error("Request Failed.\n" +
                            "Status Code: #{statusCode}")
        else if reqType and contentType != reqType
          error = new Error("Invalid content-type.\n" +
                      "Expected #{reqType} but received #{contentType}")
        if error
          console.log(error.message)
          # consume response data to free up memory
          res.resume()
          return

        res.setEncoding('utf8')
        rawData = ''
        res.on 'data', (chunk) -> rawData += chunk
        if reqType == 'application/json'
          res
            .on 'end', ->
              try
                parsedData = JSON.parse rawData
                resolve parsedData
              catch e
                console.log e.message
                reject e.message
            .on 'error', (e) ->
              console.log("Got error: #{e.message}")
              reject e

        else
          res
            .on 'end', ->
              resolve rawData
            .on 'error', (e) ->
              console.log("Got error: #{e.message}")
              reject e



module.exports = ( ctx ) ->


  # Return obj. w/ metadata & functions
  name: 'http'

  defaults:
    route:
      options:
        compile: {}
        merge: {}
        spec:
          url: 'http://nodejs.org/dist/index.json'

  promise:
    resource: promise_resource

  generate:

    default: ( rctx ) ->

      ( req, res ) ->
        url = rctx.route.options.spec + req.params.ref
        promise_resource(
          url: url
          accType: 'application/json'
        ).then (data) ->
          res.type 'json'
          res.write JSON.stringify data
          res.end()

    ref: ( rctx ) ->
      ( req, res ) ->
        url = rctx.route.options.spec + req.params.ref
        promise_resource(
          opts: {
            method: 'head'
          }
          url: url
          accType: clientAcc
        ).then (data) ->
          res.write data
          res.end()

    res: ( rctx ) ->
      ( req, res ) ->
        url = rctx.route.options.spec + req.params.ref
        promise_resource(
          url: url
          accType: clientAcc
        ).then (data) ->
          res.write data
          res.end()

    # Redirect/proxy named domains/netpaths?
    site: ( rctx ) ->
      # TODO: look along path using sitefile function
      nso = require path.join ctx.cwd, rctx.route.spec
      ( req, res ) ->
        base = nso.names[  req.params.site ]
        url = base.base+'/'+req.params.path
        u = URL.parse req.protocol+':'+url
        port = parseInt(u.port)
        promise_resource(
          opts: {
            host: u.hostname
            port: port or 80
            path: u.path
          }
          accType: clientAcc
        ).then (data) ->
          res.write data
          res.end()

    # Redirect package/format to CDN or other library
    vendor: ( rctx ) ->
      cdnjson = path.join ctx.cwd, rctx.route.spec
      if not fs.existsSync cdnjson
        cdnjson = path.join ctx.sfdir, rctx.route.spec
      if not fs.existsSync cdnjson
        log.warn "CDN requires JSON config"
        return
      cdn = require cdnjson
      ( req, res ) ->
        f = _.defaultsDeep {}, req.params
        ext = cdn[f.format].http.ext
        if f.format not of cdn
          err = "No format #{f.format}"
          res.type 500
          res.write err
          res.end()
          throw new Error err
        if f.package not of cdn[f.format].http.packages
          err = "No #{f.format} package #{f.package}"
          res.type 500
          res.write err
          res.end()
          throw new Error err
        res.redirect cdn[f.format].http.packages[f.package]+ext

    # Return registry for require-js app
    'requirejs/config': ( rctx ) ->
      res:
        data: ( dctx ) ->
          { baseUrl, paths, map, shims, main, deps } = \
            Router.parse_kw_spec rctx

          if paths and paths.startsWith '$ref:'
            paths = Router.read_xref ctx, paths.substr 5
          else if 'string' is typeof paths
            paths = {}

          if 'object' is typeof map or not map
            map = {}
    
          map["*"] = {
            "sitefile": "sf-v0"
          }

          if 'string' is typeof shims
            shims = {}

          if not shims
            shims = {}

          baseUrl: baseUrl or rctx.res.ref
          paths: paths
          map: map
          shims: shims
          deps: [ main ]

    'requirejs/main': ( rctx ) ->
      ( req, res ) ->
        url = ctx.site.base+rctx.route.spec
        rrctx = ctx.routes.resources[url]
        rjs_opts = JSON.stringify rrctx.res.data rctx
        res.type "application/javascript"
        res.write "/* Config from #{url} ( #{rrctx.route.spec} ) */ "
        res.write "requirejs.config(#{rjs_opts});"
        res.end()

    'requirejs': ( rctx ) ->
      ( req, res ) ->
        opts = _.defaultsDeep rctx.route.options, {
          stylesheets: urls: []
          scripts: urls: []
          clients: [
            type: null
            id: null
            href: null
            main: null
          ]
        }
        { view, main } = Router.parse_kw_spec rctx
        viewPugFn = path.join __dirname, '..', 'client', view
        main = ctx.site.base+rctx.route.spec+'.js'
        res.type 'html'
        res.write pugrouter.compile viewPugFn, {
          compile: rctx.route.options.compile
          merge:
            base: ctx.site.base+rctx.name
            options: opts
            query: req.query
            context: rctx
        }
        res.end()


