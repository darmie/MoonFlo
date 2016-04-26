--     MoonFlo - Flow-Based Programming for JavaScript
--     (c) 2013-2016 TheGrid (Rituwall Inc.)
--     (c) 2011-2012 Henri Bergius, Nemein
--     (c) 2016 Damilare Akinlaja
--     MoonFlo may be freely distributed under the MIT license
--
-- Baseclass for regular MoonFlo components.
EventEmitter = require 'events'
exports = {}
ports = require 'Ports'
IP = require 'IP'
_ = require 'moses'
Error = require 'Error'
class Component extends EventEmitter
  description: ''
  icon: nil
  started: false
  load: 0
  ordered: false
  outputQ: {}
  activateOnInput: true

  new: (options) =>
    options = {} unless options
    options['inPorts'] = {} unless options['inPorts']
    if options['inPorts'].__name == ports.InPorts.__name  --instanceof
      @inPorts = options['inPorts']
    else
      @inPorts =   ports.InPorts options['inPorts']

    options.outPorts = {} unless options['outPorts']
    if options['outPorts'].__name == ports.OutPorts.__name  --instanceof
      @outPorts = options['outPorts']
    else
      @outPorts =   ports.OutPorts options['outPorts']

    @icon = options['icon'] if options['icon']
    @description = options['description'] if options['description']
    @ordered = options['ordered'] if _.contains options, 'ordered'
    @activateOnInput = options['activateOnInput'] if _.contains options, 'activateOnInput'

    if type(options['process']) == 'function'
      @process options['process']

  getDescription: => @description

  isReady: => true

  isSubgraph: => false

  setIcon: (@icon) =>
    @emit 'icon', @icon
  getIcon: => @icon

  error: (e, groups = {}, errorPort = 'error') =>
    if @outPorts[errorPort] and (@outPorts[errorPort]\isAttached() or not @outPorts[errorPort]\isRequired())
      @outPorts[errorPort]\beginGroup group for group in groups
      @outPorts[errorPort]\send e
      @outPorts[errorPort]\endGroup() for group in groups
      @outPorts[errorPort]\disconnect()
      return
    Error e

  shutdown: =>
    @started = false

  -- The startup function performs initialization for the component.
  start: =>
    @started = true
    @started

  isStarted: => @started

  -- Sets process handler function
  process: (handle) =>
    unless type(handle) == 'function'
      Error "Process handler must be a function"
    unless @inPorts
      Error "Component ports must be defined before process function"
    @handle = handle
    for name in @inPorts['ports']
      port = @inPorts['ports'][name]
      do (name, port) =>
        port['name'] = name unless port['name']
        port\on 'ip', (ip) =>
          @handleIP ip, port
    @

  handleIP: (ip, port) =>
    return unless port['options']['triggering']
    result = {}
    input =   ProcessInput @inPorts, ip, @, port, result
    output =   ProcessOutput @outPorts, ip, @, result
    @load += 1
    @handle input, output, => output\done()

exports['Component'] = Component

class ProcessInput
  constructor: (@ports, @ip, @nodeInstance, @port, @result) =>
    @scope = @ip['scope']

  activate: =>
    @result['__resolved'] = false
    if @nodeInstance['ordered']
      _.push @nodeInstance['outputQ'],  @result

  has: =>
    res = true
    res and= @ports[port]['ready'] @scope for port in arguments
    res

  get: =>
    if @nodeInstance['ordered'] and @nodeInstance['activateOnInput'] and not (_.contains(@result , '__resolved'))
      @activate!
    res = @ports[port].get @scope for port in arguments
    if table.getn(arguments) == 1 then res[1] else res

  getData: =>
    ips = @get\apply @, arguments
    if table.getn(arguments) == 1
      if(ips != nil)
        if(ips['data'] != nil)
          return ips['data']
        else
          return nil
      else
        return nil
      --return ips?.data ? undefined
    results = {}
    for ip in ips
      if(ips['data'] != nil)
        _.push results , ips['data']
      else
        _.puhs results, nil
    return results

class ProcessOutput
  constructor: (@ports, @ip, @nodeInstance, @result) =>
    @scope = @ip['scope']

  activate: =>
    @result['__resolved'] = false
    if @nodeInstance['ordered']
      _.push @nodeInstance['outputQ'], @result

  isError: (err) ->
    if err.__class == Error or _.isArray(err) and table.getn(err) > 1 and err[1].__class == Error
      return true
    return false
    --err instanceof Error or
    --Array.isArray(err) and err.length > 0 and err[0] instanceof Error
    --err if err.__class.__name == error.__name or if _.isArray(err) and table.getn(err) > 0 and err[0].__class.__name == error.__name

  error: (err) =>
    multiple = _.isArray err
    err = {err} unless multiple
    if _.contains @ports, 'error' and (@ports['error']\isAttached() or not @ports['error']\isRequired())
      @sendIP 'error',   IP 'openBracket' if multiple
      @sendIP 'error', e for e in err
      @sendIP 'error',   IP 'closeBracket' if multiple
    else
      Error e for e in err

  sendIP: (port, packet) =>
    if type(packet) != 'table' or _.indexOf(IP['types'], packet['type']) == -1
      ip =   IP 'data', packet
    else
      ip = packet
    ip.scope = @scope if @scope != nil and ip['scope'] == nil
    if @nodeInstance['ordered']
      @result[port] = {} unless _.contains @result, port
      _.push @result[port], ip
    else
      @nodeInstance['outPorts'][port].sendIP ip

  send: (outputMap) =>
    if @nodeInstance['ordered'] and not (_.contains @result, '__resolved')
      @activate()
    return @error outputMap if @isError outputMap
    for port in outputMap
      packet = outputMap(port)
      @sendIP port, packet

  sendDone: (outputMap) =>
    @send outputMap
    @done()

  done: (error) =>
    @error error if error
    if @nodeInstance['ordered']
      @result['__resolved'] = true
      while table.getn(@nodeInstance['outputQ']) > 1
        result = @nodeInstance['outputQ'][1]
        break unless result['__resolved']
        for port in result
          ips = result[port]
          continue if port == '__resolved'
          for ip in ips
            @nodeInstance['outPorts'][port]\sendIP ip
        _.pop(@nodeInstance['outputQ'])
    @nodeInstance['load'] -= 1


return Component
