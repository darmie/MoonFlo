--     MoonFlo - Flow-Based Programming for MoonScript
--     (c) 2014-2015 TheGrid (Rituwall Inc.)
--      @Author Damilare Akinlaja, 2016
--     MoonFlo may be freely distributed under the MIT license
-- Baseclass for components dealing with asynchronous I/O operations. Supports throttling.

port = require "Port"
component = require "Component"
cron = require 'cron'
_ = require 'moses'

class AsyncComponent extends component.Component

  new: (@inPortName="in", @outPortName="out", @errPortName="error") =>
    unless @inPorts[@inPortName]
      error "no inPort named '#{@inPortName}'"
    unless @outPorts[@outPortName]
      error "no outPort named '#{@outPortName}'"

    @load = 0
    @q = {}
    @errorGroups = {}

    @outPorts['load'] = port.Port()

    @inPorts[@inPortName].on "begingroup", (group) =>
      return _.push @q, { name: "begingroup", data: group } if @load > 0
      _.push @errorGroups, group
      @outPorts[@outPortName]\beginGroup group

    @inPorts[@inPortName].on "endgroup", =>
      return _.push @q, { name: "endgroup" } if @load > 0
      _.pop(@errorGroups)
      @outPorts[@outPortName].endGroup()

    @inPorts[@inPortName].on "disconnect", =>
      return _.push @q, { name: "disconnect" } if @load > 0
      @outPorts[@outPortName].disconnect()
      @errorGroups = {}
      @outPorts['load']\disconnect() if @outPorts['load']\isAttached()

    @inPorts[@inPortName].on "data", (data) =>
      return _.push @q, { name: "data", data: data } if table.getn(@q) > 0
      @processData data

  processData: (data) =>
    @incrementLoad()
    @doAsync data, (err) =>
      @error err, @errorGroups, @errPortName if err
      @decrementLoad()

  incrementLoad: =>
    @load += 1
    @outPorts['load']\send @load if @outPorts['load']\isAttached()
    @outPorts['load']\disconnect() if @outPorts['load']\isAttached()

  doAsync: (data, callback) ->
    callback error "AsyncComponents must implement doAsync"

  decrementLoad: =>
    error "load cannot be negative" if @load == 0
    @load -= 1
    @outPorts['load']\send @load if @outPorts['load']\isAttached()
    @outPorts['load']\disconnect() if @outPorts['load']\isAttached()
    if type(process) != 'nil' and process['execPath'] and _.indexOf(process['execPath'],'node') != -1
      -- nextTick is faster than setTimeout on Node.js
      process['nextTick'] => @processQueue()
    else
      cron.after 0, ()=> do @processQueue
      --setTimeout =>
        --do processQueue
      --, 0

  processQueue: =>
    if @load > 0
      return
    processedData = false
    while table.getn(@q) > 0
      event = @q[1]
      switch event['name']
        when "begingroup"
          return if processedData
          @outPorts[@outPortName]\beginGroup event['data']
          _.push @errorGroups, event['data']
          _.pop(@q)
        when "endgroup"
          return if processedData
          @outPorts[@outPortName]\endGroup()
          _.pop(@errorGroups)
          _.pop(@q)
        when "disconnect"
          return if processedData
          @outPorts[@outPortName]\disconnect()
          @outPorts['load']\disconnect() if @outPorts['load']\isAttached()
          @errorGroups = {}
          _.pop @q
        when "data"
          @processData event.data
          _.pop @q
          processedData = true

  shutdown: =>
    @q = {}
    @errorGroups = {}

return AsyncComponent
