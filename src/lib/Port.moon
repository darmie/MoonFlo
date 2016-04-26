--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license

--Regular port for MoonFlo components.

EventEmitter = require 'events'
_ = require "moses"
splice = require 'splice'
Error = require 'Error'
--Allen = require 'Allen'
--Allen.import()
--require 'indexOf'



class Port extends EventEmitter
  description: ''
  required: true
  new: (@type) =>
    @type = 'all' unless @type
    @type = 'int' if @type == 'number'
    @sockets = {}
    @from = nil
    @node = nil
    @name = nil

  getId: =>
    unless @node and @name
      return 'Port'
    "#{@node}  #{string.upper @name}"

  getDataType: => @type
  getDescription: => @description

  attach: (socket) =>
    table.insert @sockets, socket
    @attachSocket socket

  attachSocket: (socket, localId = nil) =>
    @emit "attach", socket, localId

    @from = socket.from
    socket.setMaxListeners 0 if socket.setMaxListeners
    socket.on "connect", =>
      @emit "connect", socket, localId
    socket.on "begingroup", (group) =>
      @emit "begingroup", group, localId
    socket.on "data", (data) =>
      @emit "data", data, localId
    socket.on "endgroup", (group) =>
      @emit "endgroup", group, localId
    socket.on "disconnect", =>
      @emit "disconnect", socket, localId

  connect: =>
    if table.getn(@sockets) == 0
      Error " #{@getId()}: No connections available"
    socket.connect() for socket in @sockets

  beginGroup: (group) =>
    if table.getn @sockets == 0
      Error " #{@getId()}: No connections available"

    _.each @sockets, (socket) =>
      return socket.beginGroup group if socket.isConnected()
      socket.once 'connect', =>
        socket.beginGroup group
      do socket.connect!

  send: (data) =>
    if table.getn(@sockets) == 0
      Error "#{@getId()}: No connections available"

    _.each @sockets, (socket) =>
      return socket.send data if socket.isConnected()
      socket.once 'connect', =>
        socket.send data
      do socket.connect!

  endGroup: =>
    if table.getn(@sockets) == 0
      Error "#{@getId()}: No connections available"
    socket.endGroup() for socket in @sockets

  disconnect: =>
    if table.getn(@sockets) == 0
      Error "#{@getId()}: No connections available"
    socket.disconnect() for socket in @sockets

  detach: (socket) =>
    return if table.getn(@sockets) == 0
    socket = @sockets[0] unless socket
    index = _.indexOf @sockets, socket
    return if index == -1
    if @isAddressable()
      @sockets[index] = undefined
      @emit 'detach', socket, index
      return
    splice(@sockets, index, 1)
    @emit "detach", socket

  isConnected: =>
    connected = false
    _.each @sockets, (socket) =>
      if socket.isConnected()
        connected = true
    return connected


  isAddressable: => false
  isRequired: => @required

  isAttached: =>
    return true if table.getn(@sockets) > 0
    false

  listAttached: =>
    attached = {}
    for idx,socket in pairs @sockets
      continue unless socket
      _.push(attached, idx)
    attached

  canAttach: => true



return Port
