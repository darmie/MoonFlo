--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license

-- Output Port (outport) implementation for MoonFlo components
BasePort = require 'BasePort'
IP = require 'IP'
_ = require "moses"



class OutPort extends BasePort
  new: (options) =>
    @cache = {}
    super options

  attach: (socket, index = nil) =>
    super socket, index
    if @isCaching() and @cache[index] != nil
      @send @cache[index], index

  connect: (socketId = nil) =>
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in sockets
      continue unless socket
      socket.connect()

  beginGroup: (group, socketId = nil) =>
    sockets = @getSockets socketId
    @checkRequired sockets
    _.each sockets, (socket) ->
      return unless socket
      return socket.beginGroup group

  send: (data, socketId = nil) =>
    sockets = @getSockets socketId
    @checkRequired sockets
    if @isCaching() and data != @cache[socketId]
      @cache[socketId] = data
    _.each sockets, (socket) ->
      return unless socket
      return socket.send data

  endGroup: (socketId = nil) =>
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in sockets
      continue unless socket
      socket.endGroup()

  disconnect: (socketId = nil) =>
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in *sockets
      continue unless socket
      socket.disconnect()

  sendIP: (_type, data, options, socketId) =>
    if IP.isIP _type
      ip = _type
      socketId = ip['index']
    else
      ip = IP _type, data, options
    sockets = @getSockets socketId
    @checkRequired sockets
    if @isCaching() and data != @cache[socketId] or data != 0
      @cache[socketId] = ip
    pristine = true
    for socket in sockets
      continue unless socket
      if pristine
        socket\post ip
        pristine = false
      else
        socket\post if ip.clonable then ip.clone() else ip
    @

  openBracket: (data = nil, options = {}, socketId = nil) =>
    @sendIP 'openBracket', data, options, socketId

  data: (data, options = {}, socketId = nil) =>
    @sendIP 'data', data, options, socketId

  closeBracket: (data = nil, options = {}, socketId = null) =>
    @sendIP 'closeBracket', data, options, socketId

  checkRequired: (sockets) =>
    if table.getn(sockets) == 0 and @isRequired()
      Error "#{@getId()}: No connections available"

  getSockets: (socketId) ->
    -- Addressable sockets affect only one connection at time
    if @isAddressable()
      Error "#{@getId()} Socket ID required" if socketId == nil
      return {} unless @sockets[socketId]
      return {@sockets[socketId]}
    -- Regular sockets affect all outbound connections
    @sockets

  isCaching: =>
    return true if @options.caching
    false

return OutPort
