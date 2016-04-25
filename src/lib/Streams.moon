--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license

--This script is based on NoFlo's Streams.coffee

--High-level wrappers for FBP substreams processing.


--Wraps an object to be used in Substreams
--moon = require "moon"
--module "Streams", package.seeall
exports = {}
_ = require "moses"
class IP
  new: (@data) =>
  sendTo: (port) =>
    port.send @data
  getValue: =>
    return @data
  toObject: =>
    return @data

--Substream contains groups and data packets as a tree structure
class Substream
  new: (@key) =>
    @value = {}
  push: (value) =>
    table.insert @value, value
  sendTo: (port) =>
    port.beginGroup @key
    for ip in @value
      if ip.__class == Substream or ip.__class == IP
        ip.sendTo port
      else
        port.send ip
    port.endGroup!
  getKey: =>
    return @key
  getValue: =>
    switch table.getn @value
      when 0
        return nil
      when 1
        if type(@value[0].getValue) == 'function'
          if @value[0].__class.__name == Substream.__name
            obj = {}
            obj[@value[0].key] = @value[0].getValue()
            return obj
          else
            return @value[0].getValue!
        else
          return @value[0]
      else
        res = {}
        hasKeys = false
        for ip in @value
          val = if type(ip.getValue) == 'function' then ip.getValue() else ip
          if ip.__class.__name == Substream.__name
            obj = {}
            obj[ip.key] = ip.getValue!
            table.insert res, obj
          else
            table.insert res, val
        return res
  toObject: =>
    obj = {}
    obj[@key] = @getValue!
    return obj

--StreamSender sends FBP substreams atomically.
--Supports buffering for preordered output.
class StreamSender
  new: (@port, @ordered = false) =>
        @q = {}
        @resetCurrent()
        @resolved = false
  resetCurrent: =>
        @level = 0
        @current = nil
        @stack = {}
  beginGroup: (group) =>
        @level += 1
        stream = Substream group
        table.insert @stack, stream
        @current = stream
        return @
  endGroup: =>
        @level -= 1 if @level > 0
        value = table.remove @stack, 1
        if @level == 0
          table.insert @q, value
          @resetCurrent()
        else
          parent = @stack[table.getn(@stack) - 1]
          table.insert parent, value
          @current = parent
        return @
  send: (data) =>
        if @level == 0
          table.insert @q IP data
        else
          table.insert @current IP data
        return @
  done: =>
        if @ordered
          @resolved = true
        else
          @flush()
        return @
  disconnect: =>
        table.insert @q nil --disconnect packet
        return @
  flush: =>
        --Flush the buffers
        res = false
        if table.getn(@q) > 0
          for ip in @q
            if ip is nil
              @port.disconnect() if @port.isConnected()
            else
              ip.sendTo @port
          res = true
        @q = {}
        return res
  isAttached: =>
        return @port.isAttached()

--StreamReceiver wraps an inport and reads entire
--substreams as single objects.
class StreamReceiver
  new: (@port, @buffered = false, @process = nil) =>
    @q = {}
    @resetCurrent()
    @port.process = (event, payload, index) =>
      switch event
        when 'connect'
          @process 'connect', index if type(@process) == 'function'
        when 'begingroup'
          @level +=1
          stream = Substream payload
          if @level == 1
            @root = stream
            @parent = nil
          else
            @parent = @current
          @current = stream
        when 'endgroup'
          @level -=1 if @level > 0
          if @level == 0
            if @buffered
              table.insert @q, @root
              @process 'readable', index
            else
              @process 'data', @root, index if type (@process) == 'function'
            @resetCurrent()
          else
            @parent.push @current
            @current = @parent
        when 'data'
          if @level == 0
            _.push @q, IP payload
          else
            table.insert @current  IP payload
        when 'disconnect'
          @process 'disconnect', index if type(@process) == 'function'
  resetCurrent: =>
    @level = 0
    @root = nil
    @current = nil
    @parent = nil
  read: =>
    return nil if table.getn(@q) == 0
    return table.remove @q, 1


_.push exports, :IP, :Substream, :StreamSender, :StreamReceiver

return exports
