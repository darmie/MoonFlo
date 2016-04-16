--     MoonFlo - Flow-Based Programming for MoonScript
--     (c) 2014-2015 TheGrid (Rituwall Inc.)
--      @Author Damilare Akinlaja, 2016
--     MoonFlo may be freely distributed under the MIT license
--
--ArrayPorts are similar to regular ports except that they're able to handle multiple
--connections and even address them separately.
port = require "Port"
_ = require 'moses'
class ArrayPort extends port.Port
  constructor: (@type) ->
    super @type

  attach: (socket, socketId = nil) ->
    socketId = table.getn(@sockets) if socketId == nil
    @sockets[socketId] = socket
    @attachSocket socket, socketId

  connect: (socketId = nil) ->
    if socketId == nil
      unless table.getn @sockets
        error "#{@getId()}: No connections available"
      _.each @sockets, (key, socket) ->
        return unless socket
        socket\connect()
      return

    unless @sockets[socketId]
      error "#{@getId()}: No connection '#{socketId}' available"

    @sockets[socketId]\connect()

  beginGroup: (group, socketId = nil) ->
    if socketId is nil
      unless table.getn @sockets
        error "#{@getId()}: No connections available"
      _.each @sockets, (index, socket) =>
        return unless socket
        @beginGroup group, index
      return

    unless @sockets[socketId]
      error "#{@getId()}: No connection '#{socketId}' available"

    return @sockets[socketId]\beginGroup group if @isConnected socketId

    @sockets[socketId]\once "connect", =>
      @sockets[socketId]\beginGroup group
    @sockets[socketId]\connect()

  send: (data, socketId = nil) =>
    if socketId == nil
      unless table.getn @sockets
        error "#{@getId()}: No connections available"
      _.each @sockets, (index,socket) =>
        return unless socket
        @send data, index
      return

    unless @sockets[socketId]
      error "#{@getId()}: No connection '#{socketId}' available"

    return @sockets[socketId]\send data if @isConnected socketId

    @sockets[socketId]\once "connect", =>
      @sockets[socketId]\send data
    @sockets[socketId]\connect()

  endGroup: (socketId = nil) ->
    if socketId == nil
      unless table.getn @sockets
        error "#{@getId()}: No connections available"
      _.each @sockets, (index,socket) =>
        return unless socket
        @endGroup index
      return

    unless @sockets[socketId]
      error "#{@getId()}: No connection '#{socketId}' available"

    do @sockets[socketId]\endGroup!

  disconnect: (socketId = nil) ->
    if socketId == nil
      unless table.getn @sockets
        error "#{@getId()}: No connections available"
      for socket in @sockets
        return unless socket
        socket\disconnect()
      return

    return unless @sockets[socketId]
    @sockets[socketId]\disconnect()

  isConnected: (socketId = nil) ->
    if socketId is nil
      connected = false
      _.each @sockets, (key ,socket) =>
        return unless socket
        if socket\isConnected()
          connected = true
      return connected

    unless @sockets[socketId]
      return false
    @sockets[socketId]\isConnected()

  isAddressable: -> true

  isAttached: (socketId) =>
    if socketId == undefined
      for socket in @sockets
        return true if socket
      return false
    return true if @sockets[socketId]
    false

return ArrayPort
