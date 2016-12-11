

module.exports = ( ctx ) ->

  name: 'sf-example'

  generate:
    default: ( rctx, rsinit ) ->
      ( req, res ) ->
        res.type 'text'
        res.write 'Sitefile example'
        res.end()

    data1: ( rctx, rsinit ) ->
      res:
        data: ->
          'sf-example': 'dynamic'

    data2: ( rctx, rsinit ) ->
      res:
        data:
          'sf-example': 'static'
      

