attr = require('attr-accessor')
express = require('express')
find = require('array-find')
ADT = require('blizzardry/lib/adt')
Archive = require('./archive')
BLP = require('blizzardry/lib/blp')
{DecodeStream} = require('blizzardry/lib/restructure')
DBC = require('blizzardry/lib/dbc/entities')
{PNG} = require('pngjs')

# TODO: Find a module for this
flatten = (array) ->
  array.reduce (a, b) -> a.concat(b)

class Pipeline
  module.exports = this

  [get] = attr.accessors(this)

  DATA_DIR = 'data'

  constructor: ->
    @router = express()
    @router.param 'resource', @resource.bind(this)
    @router.get '/:resource(*.blp).png', @blp.bind(this)
    @router.get '/:resource(*.dbc)/:id(*)?.json', @dbc.bind(this)
    @router.get '/:resource(*.adt).3js', @adt.bind(this)
    @router.get '/find/:query', @find.bind(this)
    @router.get '/:resource', @serve.bind(this)

  get archive: ->
    @_archive ||= Archive.build(DATA_DIR)

  resource: (req, res, next, path) ->
    req.resourcePath = path
    if req.resource = @archive.files.get path
      next()
    else
      err = new Error 'resource not found'
      err.status = 404
      throw err

  blp: (req, res) ->
    BLP.from req.resource.data, (blp) ->
      mipmap = blp.largest

      png = new PNG(width: mipmap.width, height: mipmap.height)
      png.data = mipmap.rgba

      res.set 'Content-Type', 'image/png'
      png.pack().pipe(res)

  dbc: (req, res) ->
    name = req.resourcePath.match(/(\w+)\.dbc/)[1]
    if definition = DBC[name]
      dbc = definition.dbc.decode new DecodeStream(req.resource.data)
      if id = req.params[0]
        if entity = find(dbc.records, (entity) -> String(entity.id) == id)
          res.send entity
        else
          err = new Error 'entity not found'
          err.status = 404
          throw err
      else
        res.send dbc.records
    else
      err = new Error 'entity definition not found'
      err.status = 404
      throw err

  adt: (req, res) ->
    adt = ADT.decode new DecodeStream(req.resource.data)

    size = 33.333333
    step = size / 8

    faces = []
    vertices = []

    # See: http://www.pxr.dk/wowdev/wiki/index.php?title=ADT#MCVT_sub-chunk
    for cy in [0...16]
      for cx in [0...16]
        cindex = cy * 16 + cx
        chunk = adt.MCNKs[cindex]

        chunk.MCVT.heights.forEach (height, index) ->
          y = index // 17
          x = index % 17
          if x > 8
            y += 0.5
            x -= 8.5
          vertices.push cx * size + x * step, cy * size + y * step, chunk.position.z + height

        coffset = cindex * 145
        index = coffset + 9
        for y in [0...8]
          for x in [0...8]
            faces.push 0, index, index - 9, index - 8
            faces.push 0, index, index - 8, index + 9
            faces.push 0, index, index + 9, index + 8
            faces.push 0, index, index + 8, index - 9
            index++
          index += 9

    res.send {
      vertices: vertices
      faces: faces
    }

  find: (req, res) ->
    res.send @archive.files.find req.params.query

  serve: (req, res) ->
    res.send req.resource.data
