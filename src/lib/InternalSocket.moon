--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license

--module "InternalSocket", package.seeall
exports = {}
--print(package.path)
--  on production set path to search from project root package.path = package.path .. ";?.lua;"
-- moon = require 'moonscript'
IP = require 'IP'    --- remember to overide require using moon.loadfile 'IP'
EventEmitter = require 'events'
Allen = require "Allen"
Allen.import()

Error = require "Error"
---- Internal Sockets
----
----The default communications mechanism between MoonFlo processes is
----an _internal socket_, which is responsible for accepting information
----packets sent from processes' outports, and emitting corresponding
----events so that the packets can be caught to the inport of the
----connected process.
class InternalSocket extends EventEmitter
  regularEmitEvent: (event, data) =>
    @emit event, data

  debugEmitEvent: (event, data) =>
    success, err = @emit event, data
    if err
      Error(err) if table.getn(@listeners('error')) == 0
      @emit 'error',
        id: @to['process']['id']
        error: Error
        metadata: @metadata

  new: (@metadata = {}) =>
    @brackets = {}
    @dataDelegate = nil
    @debug = false
    @emitEvent = @regularEmitEvent

  ---- Socket connections
  ----
  ----Sockets that are attached to the ports of processes may be
  ----either connected or disconnected. The semantical meaning of
  ----a connection is that the outport is in the process of sending
  ----data. Disconnecting means an end of transmission.
  ----
  ----This can be used for example to signal the beginning and end
  ----of information packets resulting from the reading of a single
  ----file or a database query.
  ----
  ----Example, disconnecting when a file has been completely read:
  ----
  ----    readBuffer: (fd, position, size, buffer) ->
  ----      fs.read fd, buffer, 0, buffer.length, position, (err, bytes, buffer) =>
  ----        ----Send data. The first send will also connect if not
  ----        ----already connected.
  ----        @outPorts.out.send buffer.slice 0, bytes
  ----        position += buffer.length
  ----
  ----        ----Disconnect when the file has been completely read
  ----        return @outPorts.out.disconnect() if position >= size
  ----
  ----        ----Otherwise, call same method recursively
  ----        @readBuffer fd, position, size, buffer
  connect: =>
    @handleSocketEvent 'connect', nil

  disconnect: =>
    @handleSocketEvent 'disconnect', nil

  isConnected: => table.getn(@brackets) > 0

  ---- Sending information packets
  ----
  ----The _send_ method is used by a processe's outport to
  ----send information packets. The actual packet contents are
  ----not defined by MoonFlo, and may be any valid JavaScript data
  ----structure.
  ----
  ----The packet contents however should be such that may be safely
  ----serialized or deserialized via JSON. This way the MoonFlo networks
  ----can be constructed with more flexibility, as file buffers or
  ----message queues can be used as additional packet relay mechanisms.
  send: (data) =>
    data = @dataDelegate() if data == nil and type(@dataDelegate) == 'function'
    @handleSocketEvent 'data', data

  ---- Sending information packets without open bracket
  ----
  ----As _connect_ event is considered as open bracket, it needs to be followed
  ----by a _disconnect_ event or a closing bracket. In the new simplified
  ----sending semantics single IP objects can be sent without open/close brackets.
  post: (data) =>
    data = @dataDelegate() if data == nil and type(@dataDelegate) == 'function'
    @emitEvent 'connect', @ if data.type == 'data' and table.getn(@brackets) == 0
    @handleSocketEvent 'data', data, false
    @emitEvent 'disconnect', @ if data.type == 'data' and table.getn(@brackets) == 0

  ---- Information Packet grouping
  ----
  ----Processes sending data to sockets may also group the packets
  ----when necessary. This allows transmitting tree structures as
  ----a stream of packets.
  ----
  ----For example, an object could be split into multiple packets
  ----where each property is identified by a separate grouping:
  ----
  ----    ----Group by object ID
  ----    @outPorts.out.beginGroup object.id
  ----
  ----    for property, value of object
  ----      @outPorts.out.beginGroup property
  ----      @outPorts.out.send value
  ----      @outPorts.out.endGroup()
  ----
  ----    @outPorts.out.endGroup()
  ----
  ----This would cause a tree structure to be sent to the receiving
  ----process as a stream of packets. So, an article object may be
  ----as packets like:
  ----
  ----* `/<article id>/title/Lorem ipsum`
  ----* `/<article id>/author/Henri Bergius`
  ----
  ----Components are free to ignore groupings, but are recommended
  ----to pass received groupings onward if the data structures remain
  ----intact through the component's processing.
  beginGroup: (group) =>
    @handleSocketEvent 'begingroup', group

  endGroup: =>
    @handleSocketEvent 'endgroup'

  ---- Socket data delegation
  ----
  ----Sockets have the option to receive data from a delegate function
  ----should the `send` method receive undefined for `data`.  This
  ----helps in the case of defaulting values.
  setDataDelegate: (delegate) =>
    unless typee(delegate) == 'function'
      Error 'A data delegate must be a function.'
    @dataDelegate = delegate

  ---- Socket debug mode
  ----
  ----Sockets can catch exceptions happening in processes when data is
  ----sent to them. These errors can then be reported to the network for
  ----notification to the developer.
  setDebug: (active) =>
    @debug = active
    @emitEvent = if @debug then @debugEmitEvent else @regularEmitEvent

  ---- Socket identifiers
  ----
  ----Socket identifiers are mainly used for debugging purposes.
  ----Typical identifiers look like _ReadFile:OUT -> Display:IN_,
  ----but for sockets sending initial information packets to
  ----components may also loom like _DATA -> ReadFile:SOURCE_.
  getId: =>
    fromStr = (_from) ->
      "#{_from['process']['id']}() #{string.capitalize(_from['port'])}"
    toStr = (to) ->
      "#{to['port']} #{to['process']['id']}()"

    return "UNDEFINED" unless @from or @to
    return "#{fromStr(@from)} -> ANON" if @from and not @to
    return "DATA -> #{toStr(@to)}" unless @from
    "#{fromStr(@from)} -> #{toStr(@to)}"

  legacyToIp: (event, payload) =>
    ----No need to wrap modern IP Objects
    return payload if IP.isIP payload

    ----Wrap legacy events into appropriate IP objects
    switch event
      when 'connect', 'begingroup'
        return IP 'openBracket', payload
      when 'disconnect', 'endgroup'
        return IP 'closeBracket'
      else
        return IP 'data', payload

  ipToLegacy: (ip) =>
    switch ip.type
      when 'openBracket'
        if table.getn(@brackets) == 1
          return{
            event: 'connect'
            payload: @
           }
        else
          return{
           event: 'begingroup'
           payload: ip.data
          }
      when "data"
        legacy =
          event: 'data'
          payload: ip.data
        return legacy
      when 'closeBracket'
        if table.getn(@brackets) == 0
          return {
            event: 'disconnect'
            payload: @
           }
        return {
          event: 'endgroup'
          payload: ip.data
         }

  handleSocketEvent: (event, payload, autoConnect = true) =>
    ip = @legacyToIp event, payload

    ----Handle state transitions
    if ip.type == 'data' and table.getn(@brackets) == 0 and autoConnect
      ----Connect before sending data
      @handleSocketEvent 'connect', nil

    if ip.type == 'openBracket'
      if ip.data == nil
        ----If we're already connected, no need to connect again
        return if table.getn(@brackets)
      else
        if table.getn(@brackets) == 0 and autoConnect
          ----Connect before sending bracket
          @handleSocketEvent 'connect', nil
      @brackets.push ip.data

    if ip.type == 'closeBracket'
      ----Last bracket was closed, we're disconnected
      ----If we were already disconnected, no need to disconnect again
      return if table.getn(@brackets) == 0
      ----Add group name to bracket
      ip.data = @brackets.pop()

    ----Emit the IP Object
    @emitEvent 'ip', ip

    ----Emit the legacy event
    legacyEvent = @ipToLegacy ip
    @emitEvent legacyEvent.event, legacyEvent.payload

exports['InternalSocket'] = InternalSocket

exports['createSocket'] = ->  InternalSocket!

return exports
