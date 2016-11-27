path = require 'path'
cc = require 'coffee-script'



module.exports = ( ctx ) ->


  httprouter = require('./http') ctx
  pugrouter = require('./pug') ctx
  
  detailPugFn = path.join( __dirname, 'require-js/view/detail.pug' )

  listPugFn = path.join( __dirname, 'require-js/view/list.pug' )
  listCoffeeFn = path.join( __dirname, 'require-js/view/list.coffee' )


  # Export router object

  name: 'require-js'

  route:
    default: '.default'
    ps: ( rctx ) ->

    bootstrap:
      css:
        cdn: [
          '//cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.0.0-alpha.5/css/bootstrap.min'
          '//cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.0.0-alpha.5/js/bootstrap.min.js'
          '//cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.0.0-alpha.5/css/bootstrap.min.css.map'
        ]

  generate:
    default: ( rctx ) ->

      console.log 'PM2', ctx.site.base, rctx.name, rctx.res, rctx.route
      if not rctx.res.path
        throw Error "JSON path expected"

      data = require path.join '../../..', rctx.res.path

      null

    ps: ( rctx ) ->

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
              options: rctx.options
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
              base: ctx.site.base+rctx.name
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

      null

