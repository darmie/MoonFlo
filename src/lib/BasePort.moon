---     MoonFlo - Flow-Based Programming for MoonScript
--     (c) 2014-2015 TheGrid (Rituwall Inc.)
--      @Author Damilare Akinlaja, 2016
--     MoonFlo may be freely distributed under the MIT license
--Base port type used for options normalization
EventEmitter = require 'events'
_ = require "moses"
Allen = require "Allen"
Allen.import()
validTypes = {
  'all'
  'string'
  'number'
  'int'
  'object'
  'array'
  'boolean'
  'color'
  'date'
  'bang'
  'function'
  'buffer'
}

class BasePort extends EventEmitter
  new: (options) =>
    @handleOptions options
    @sockets = {}
    @node = nil
    @name = nil

  handleOptions: (options) =>
    options = {} unless options
    options['datatype'] = 'all' unless options['datatype']
    options['required'] = false if options['required'] == nil

    options['datatype'] = 'int' if options['datatype'] == 'integer'
    if _.indexOf(validTypes, options['datatype']) == -1
      error "Invalid port datatype '#{options['datatype']}' specified, valid are #{_.concat(validTypes, ', ')}"

    if options['type'] and _.indexOf(options['type'], '/') == -1
      error "Invalid port type '#{options['type']}' specified. Should be URL or MIME type"

    @options = options

  getId: =>
    unless @node and @name
      return 'Port'
    "#{@node} #{string.capitalize(@name)}" 

  getDataType: => @options['datatype']
  getDescription: => @options['description']

  attach: (socket, index = nil) =>
    if not @isAddressable() or index == nil
      index = table.getn @sockets
    @sockets[index] = socket
    @attachSocket socket, index
    if @isAddressable()
      @emit 'attach', socket, index
      return
    @emit 'attach', socket

  attachSocket: =>

  detach: (socket) =>
    index = _.indexOf @sockets, socket
    if index == -1
      return
    @sockets[index] = nil
    if @isAddressable()
      @emit 'detach', socket, index
      return
    @emit 'detach', socket

  isAddressable: =>
    return true if @options['addressable']
    false

  isBuffered: =>
    return true if @options['buffered']
    false

  isRequired: =>
    return true if @options['required']
    false

  isAttached: (socketId = nil) ->
    if @isAddressable() and socketId != nil
      return true if @sockets[socketId]
      return false
    return true if table.getn @sockets
    false

  listAttached: =>
    attached = {}
    for socket, idx in @sockets
      continue unless socket
      _.push attached, idx
    attached

  isConnected: (socketId = nil) =>
    if @isAddressable()
      error "#{@getId()}: Socket ID required" if socketId == nil
      error "#{@getId()}: Socket #{socketId} not available" unless @sockets[socketId]
      return @sockets[socketId]\isConnected()

    connected = false
    _.each @sockets, (key, socket) =>
      return unless socket
      if socket\isConnected()
        connected = true
    return connected

  canAttach: => true

export BasePort = BasePort
return BasePort
