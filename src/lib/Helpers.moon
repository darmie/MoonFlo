--     MoonFlo - Flow-Based Programming for MoonScript
--     (c) 2014-2015 TheGrid (Rituwall Inc.)
--      @Author Damilare Akinlaja, 2016
--     MoonFlo may be freely distributed under the MIT license
module "Helpers", package.seeall
export MapComponent
export WirePattern
export GroupedInput
export MultiError
export CustomError
export CustomizeError

_ = require 'moses'
StreamSender = require('Streams').StreamSender
StreamReceiver = require('Streams').StreamReceiver
InternalSocket = require 'InternalSocket'

isArray = (obj) ->
  return _.isArray(obj) if _.isArray
  return '[object Array]' --Object.prototype.toString.call(arg) == '[object Array]'

-- MapComponent maps a single inport to a single outport, forwarding all
-- groups from in to out and calling `func` on each incoming packet
MapComponent = (component, func, config) ->
  config = {} unless config
  config['inPort'] = 'in' unless config['inPort']
  config['outPort'] = 'out' unless config['outPort']

  inPort = component['inPorts'][config['inPort']]
  outPort = component['outPorts'][config['outPort']]
  groups = {}
  inPort['process'] = (event, payload) ->
    switch event
      when 'connect' then outPort\connect()
      when 'begingroup'
        _.push groups, payload
        outPort\beginGroup payload
      when 'data'
        func payload, groups, outPort
      when 'endgroup'
        _.pop groups
        outPort\endGroup()
      when 'disconnect'
        groups = {}
        outPort\disconnect()

-- WirePattern makes your component collect data from several inports
-- and activates a handler `proc` only when a tuple from all of these
-- ports is complete. The signature of handler function is:
-- ```
-- proc = (combinedInputData, inputGroups, outputPorts, asyncCallback) ->
-- ```
--
-- With `config.group = true` it checks incoming group IPs and collates
-- data with matching group IPs. By default this kind of grouping is `false`.
-- Set `config.group` to a RegExp object to correlate inputs only if the
-- group matches the expression (e.g. `^req_`). For non-matching groups
-- the component will act normally.
--
-- With `config.field = 'fieldName' it collates incoming data by specified
-- field. The component's proc function is passed a combined object with
-- port names used as keys. This kind of grouping is disabled by default.
--
-- With `config.forwardGroups = true` it would forward group IPs from
-- inputs to the output sending them along with the data. This option also
-- accepts string or array values, if you want to forward groups from specific
-- port(s) only. By default group forwarding is `false`.
--
-- `config.receiveStreams = [portNames]` feature makes the component expect
-- substreams on specific inports instead of separate IPs (brackets and data).
-- It makes select inports emit `Substream` objects on `data` event
-- and silences `beginGroup` and `endGroup` events.
--
-- `config.sendStreams = [portNames]` feature makes the component emit entire
-- substreams of packets atomically to the outport. Atomically means that a
-- substream cannot be interrupted by other packets, which is important when
-- doing asynchronous processing. In fact, `sendStreams` is enabled by default
-- on all outports when `config.async` is `true`.
--
-- WirePattern supports both sync and async `proc` handlers. In latter case
-- pass `config.async = true` and make sure that `proc` accepts callback as
-- 4th parameter and calls it when async operation completes or fails.
--
-- WirePattern sends group packets, sends data packets emitted by `proc`
-- via its `outputPort` argument, then closes groups and disconnects
-- automatically.
WirePattern = (component, config, proc) ->
  -- In ports
  inPorts = if _.contains config, 'in' then config['in'] else 'in'
  inPorts = {inPorts} unless _.isArray inPorts
  -- Out ports
  outPorts = if _.contains config, 'out'  then config['out'] else 'out'
  outPorts = { outPorts } unless _.isArray outPorts
  -- Error port
  config['error'] = 'error' unless _contains config, 'error'
  -- For async process
  config['async'] = false unless _.contains config, 'async'
  -- Keep correct output order for async mode
  config['ordered'] = true unless _.contains config, 'ordered'
  -- Group requests by group ID
  config['group'] = false unless _.contains config, 'group'
  -- Group requests by object field
  config['field'] = nil unless _.contains config, 'field'
  -- Forward group events from specific inputs to the output:
  -- - false: don't forward anything
  -- - true: forward unique groups of all inputs
  -- - string: forward groups of a specific port only
  -- - array: forward unique groups of inports in the list
  config['forwardGroups'] = false unless  _.contains config, 'forwardGroups'
  -- Receive streams feature
  config['receiveStreams'] = false unless _.contains config, 'receiveStreams'
  if type(config['receiveStreams']) == 'string'
    config['receiveStreams'] = { config['receiveStreams'] }
  -- Send streams feature
  config['endStreams'] = false unless _.contains config,'sendStreams'
  if type(config['sendStreams']) == 'string'
    config['sendStreams'] = { config['sendStreams'] }
  config['sendStreams'] = outPorts if config['async']
  -- Parameter ports
  config['params'] = {} unless _.contains config, 'params'
  config['params'] = { config.params } if type(config['params']) == 'string'
  -- Node name
  config['name'] = '' unless _.contains config, 'name'
  -- Drop premature input before all params are received
  config['dropInput'] = false unless _.contains config, 'dropInput'
  -- Firing policy for addressable ports
  unless _.contains config, 'arrayPolicy'
    config['arrayPolicy'] =
      in: 'any'
      params: 'all'
  -- Garbage collector frequency: execute every N packets
  config['gcFrequency'] = 100 unless _.contains config, 'gcFrequency'
  -- Garbage collector timeout: drop packets older than N seconds
  config['gcTimeout'] = 300 unless _.contains config, 'gcTimeout'

  collectGroups = config['forwardGroups']
  -- Collect groups from each port?
  if type(collectGroups) == 'boolean' and not config['group']
    collectGroups = inPorts
  -- Collect groups from one and only port?
  if type(collectGroups) == 'string' and not config['group']
    collectGroups = {collectGroups}
  -- Collect groups from any port, as we group by them
  if collectGroups != false and config['group']
    collectGroups = true

  for name in inPorts
    unless component['inPorts'][name]
      error "no inPort named '--{name}'"
  for name in outPorts
    unless component['outPorts'][name]
      error "no outPort named '--{name}'"

  component['groupedData'] = {}
  component['groupedGroups'] = {}
  component['groupedDisconnects'] = {}

  disconnectOuts = ->
    -- Manual disconnect forwarding
    for p in outPorts
      component['outPorts'][p]\disconnect() if component['outPorts'][p]\isConnected()

  sendGroupToOuts = (grp) ->
    for p in outPorts
      component['outPorts'][p]\beginGroup grp

  closeGroupOnOuts = (grp) ->
    for p in outPorts
      component['outPorts'][p]\endGroup grp

  -- For ordered output
  component.outputQ = {}
  processQueue = ->
    while table.getn(component['outputQ']) > 0
      streams = component['outputQ'][0]
      flushed = false
      -- nil in the queue means "disconnect all"
      if streams is nil
        disconnectOuts()
        flushed = true
      else
        -- At least one of the outputs has to be resolved
        -- for output streams to be flushed.
        if table.getn(outPorts) == 1
          tmp = {}
          tmp[outPorts[0]] = streams
          streams = tmp
        for key, stream in streams
          if stream['resolved']
            stream\flush()
            flushed = true
      _.pop component['outputQ'] if flushed
      return unless flushed

  if config['async']
    component['load'] = 0 if _.contains component['outPorts'], 'load'
    -- Create before and after hooks
    component['beforeProcess'] = (outs) ->
      _.push component['outputQ'], outs if config['ordered']
      component['load'] += 1
      if _.contains component['outPorts'],'load'  and component['outPorts']['load']\isAttached()
        component['outPorts']['load']\send component['load']
        component['outPorts']['load']\disconnect()
    component['afterProcess'] = (err, outs) ->
      processQueue()
      component['load'] -= 1
      if _.contains component['outPorts'], 'load'  and component['outPorts']['load']\isAttached()
        component['outPorts']['load']\send component['load']
        component['outPorts']['load']\disconnect()

  -- Parameter ports
  component['taskQ'] = {}
  component['params'] = {}
  component['requiredParams'] = {}
  component['completeParams'] = {}
  component['eceivedParams'] = {}
  component['defaultedParams'] = {}
  component['defaultsSent'] = false

  component['sendDefaults'] = ->
    if table.getn(component['defaultedParams']) > 0
      for param in component['defaultedParams']
        if _.indexOf(component['receivedParams'], param) == -1
          tempSocket = InternalSocket\createSocket()
          component['inPorts'][param]\attach tempSocket
          tempSocket\send()
          tempSocket\disconnect()
          component['inPorts'][param]\detach tempSocket
    component['defaultsSent'] = true

  resumeTaskQ = ->
    if table.getn(component['completeParams']) == table.getn(component['requiredParams']) and
    table.getn(component['taskQ']) > 0
      -- Avoid looping when feeding the queue inside the queue itself
      temp = _.slice component['taskQ'],  0
      component['taskQ'] = {}
      while table.getn(temp) > 0
        task = _.pop(temp)
        task()
  for port in config['params']
    unless component['inPorts'][port]
      error "no inPort named '--{port}'"
    _.push(component['requiredParams'], port) if component['inPorts'][port]\isRequired()
    _.push(component['defaultedParams'], port) if component['inPorts'][port]\hasDefault()
  for port in config['params']
    do (port) ->
      inPort = component['inPorts'][port]
      inPort['process'] = (event, payload, index) ->
        -- Param ports only react on data
        return unless event == 'data'
        if inPort\isAddressable()
          component['params'][port] = {} unless  _.contains component['params'], port
          component['params'][port][index] = payload
          if config['arrayPolicy']['params'] == 'all' and
          table.getn(_.keys(component['params'][port])) < table.getn(inPort\listAttached())
            return -- Need data on all array indexes to proceed
        else
          component['params'][port] = payload
        if _.indexOf(component['completeParams'], port) == -1 and
        _.indexOf(component['requiredParams'], port) > -1
          _.push component['completeParams'],  port
        _.push component['receivedParams'],  port
        -- Trigger pending procs if all params are complete
        resumeTaskQ()

  -- Disconnect event forwarding
  component['disconnectData'] = {}
  component['disconnectQ'] = {}

  component['groupBuffers'] = {}
  component['keyBuffers'] = {}
  component['gcTimestamps'] = {}

  -- Garbage collector
  component['dropRequest'] = (key) ->
    -- Discard pending disconnect keys
    table.remove(component['disconnectData'], key) if _.contains component['disconnectData'], key
    -- Clean grouped data
    table.remove(component['groupedData'], key) if  _.contains component['groupedData'], key
    table.remove(component['groupedGroups'], key) if _.contains component['groupedGroups'], key

  component['gcCounter'] = 0
  gc = ->
    component['gcCounter'] += 1
    if component['gcCounter'] % config['gcFrequency'] == 0
      current = os.time()
      for key, val in component['gcTimestamps']
        if (current - val) > (config['gcTimeout'] * 1000)
          component\dropRequest key
          table.remove(component['gcTimestamps'], key)

  -- Grouped ports
  for port in inPorts
    do (port) ->
      component['groupBuffers'][port] = {}
      component['keyBuffers'][port] = nil
      -- Support for StreamReceiver ports
      if config['receiveStreams'] and _.indexOf(config['receiveStreams'], port) != -1
        inPort = StreamReceiver component['inPorts'][port]
      else
        inPort = component['inPorts'][port]

      needPortGroups = type(collectGroups) == 'table' and _.indexOf(collectGroups, port) != -1

      -- Set processing callback
      inPort['process'] = (event, payload, index) ->
        component['groupBuffers'][port] = {} unless component['groupBuffers'][port]
        switch event
          when 'begingroup'
            _.push component['groupBuffers'][port], payload
            if config['forwardGroups'] and (collectGroups == true or needPortGroups) and not config['async']
              sendGroupToOuts payload
          when 'endgroup'
            component['groupBuffers'][port] = _.slice(component['groupBuffers'][port], 0 , component['groupBuffers'][port].length - 1)
            if config['forwardGroups'] and (collectGroups == true or needPortGroups) and not config['async']
              closeGroupOnOuts payload
          when 'disconnect'
            if table.getn(inPorts) == 1
              if config['async'] or config['StreamSender']
                if config['ordered']
                  _.push component['outputQ'], nil
                  processQueue()
                else
                  _.push(component['disconnectQ'], true)
              else
                disconnectOuts()
            else
              foundGroup = false
              key = component['keyBuffers'][port]
              component['disconnectData'][key] = {} unless _.contains component.disconnectData, key
              placebo = {}
              for k = 0, table.getn(component['disconnectData'][key])
                _.push placebo, k
              for i in placebo
                unless  _.contains component['disconnectData'][key][i], port
                  foundGroup = true
                  component['disconnectData'][key][i][port] = true
                  if table.getn(_.keys(component['disconnectData'][key][i])) == table.getn(inPorts['length'])
                    _.pop(component['disconnectData'][key])
                    if config['async'] or config['StreamSender']
                      if config['ordered']
                        _.push component['outputQ'], nil
                        processQueue()
                      else
                        _.push component['disconnectQ'], true
                    else
                      disconnectOuts()
                    table.remove(component['disconnectData'], key) if table.getn(component['disconnectData'][key]) == 0
                  break
              unless foundGroup
                obj = {}
                obj[port] = true
                _.push component['disconnectData'][key], obj

          when 'data'
            if table.getn(inPorts) == 1 and not inPort\isAddressable()
              data = payload
              groups = component['groupBuffers'][port]
            else
              key = ''
              if config['group'] and table.getn(component['groupBuffers'][port]) > 0
                key = json.encode(component['groupBuffers'][port])
                --if config.group instanceof RegExp
                  --reqId = nil
                  --for grp in component.groupBuffers[port]
                    --if config.group.test grp
                      --reqId = grp
                      --break
                  --key = nil if reqId then reqId else ''
              else if config['field'] and type(payload) == 'table' and
              _.contains payload, config['field']
                key = payload[config['field']]
              component['keyBuffers'][port] = key

              component['groupedData'][key] = {} unless _.contains component['groupedData'], key
              component['groupedGroups'][key] = {} unless _.contains component['groupedGroups'], key
              foundGroup = false
              requiredLength = table.getn(inPorts)
              requiredLength += 1 if config['field']
              -- Check buffered tuples awaiting completion
              placebo = {}
              for j = 0, table.getn component['groupedData'][key]
                _.push placebo, j

              for i in placebo
                -- Check this buffered tuple if it's missing value for this port
                if not (_.contains(component['groupedData'][key][i], port)) or
                (component['inPorts'][port]\isAddressable() and
                config['arrayPolicy']['in'] == 'all' and
                not (_.contains(component['groupedData'][key][i][port], index)))
                  foundGroup = true
                  if component['inPorts'][port]\isAddressable()
                    -- Maintain indexes for addressable ports
                    unless _.contains(component['groupedData'][key][i], port)
                      component['groupedData'][key][i][port] = {}
                    component['groupedData'][key][i][port][index] = payload
                  else
                    component['groupedData'][key][i][port] = payload
                  if needPortGroups
                    -- Include port groups into the set of the unique ones
                    component['groupedGroups'][key][i] = _.union component['groupedGroups'][key][i], component['groupBuffers'][port]
                  else if collectGroups == true
                    -- All the groups we need are here in this port
                    component['groupedGroups'][key][i][port] = component['groupBuffers'][port]
                  -- Addressable ports may require other indexes
                  if component['inPorts'][port]\isAddressable() and
                  config['arrayPolicy']['in'] == 'all' and
                  table.getn(_.keys(component['groupedData'][key][i][port])) <
                  table.getn(component['inPorts'][port]\listAttached())
                    return -- Need data on other array port indexes to arrive

                  groupLength = table.getn(_.keys(component['groupedData'][key][i]))
                  -- Check if the tuple is complete
                  if groupLength == requiredLength
                    splice = require 'splice'
                    data = splice(component['groupedData'][key] i, 1)[0]
                    -- Strip port name if there's only one inport
                    if table.getn(inPorts) == 1 and inPort\isAddressable()
                      data = data[port]
                    groups = splice(component['groupedGroups'][key] i, 1)[0]
                    if collectGroups == true
                      groups = _.intersection.apply nil, _.values groups
                    table.remove(component['groupedData'], key) if table.getn(component['groupedData'][key])== 0
                    table.remove(component['groupedGroups'], key) if table.getn(component['groupedGroups'][key])== 0
                    if config['group'] and key
                      delete component['gcTimestamps'][key]
                    break
                  else
                    return -- need more data to continue
              unless foundGroup
                -- Create a new tuple
                obj = {}
                obj[config['field']] = key if config['field']
                if component['inPorts'][port].isAddressable()
                  if obj[port] == nil then obj[port] = {} else obj[port][index] = payload
                else
                  obj[port] = payload
                if table.getn(inPorts) == 1 and
                component['inPorts'][port]\isAddressable() and
                (config['arrayPolicy']['in'] == 'any' or
                table.getn(component['inPorts'][port]\listAttached())== 1)
                  -- This packet is all we need
                  data = obj[port]
                  groups = component['groupBuffers'][port]
                else
                  _.push component['groupedData'][key], obj
                  if needPortGroups
                    _.push component['groupedGroups'][key], component['groupBuffers'][port]
                  else if collectGroups == true
                    if tmp == nil then tmp = {} else  tmp[port] = component['groupBuffers'][port]
                    _.push component['groupedGroups'][key],  tmp
                  else
                    _.push component['groupedGroups'][key], {}
                  if config['group'] and key
                    -- Timestamp to garbage collect this request
                    component['gcTimestamps'][key] = os.time()
                  return -- need more data to continue

            -- Drop premature data if configured to do so
            return if config['dropInput'] and table.getn component['completeParams'] != table.getn component['requiredParams']

            -- Prepare outputs
            outs = {}
            for name in outPorts
              if config['async'] or config['sendStreams'] and
              _.indexOf(config['sendStreams'], name) != -1
                outs[name] = StreamSender component['outPorts'][name], config['ordered']
              else
                outs[name] = component['outPorts'][name]

            outs = outs[outPorts[0]] if outPorts.length == 1 -- for simplicity
            groups = {} unless groups
            whenDoneGroups = _.slice groups, 0
            whenDone = (err) ->
              if err
                component.error err, whenDoneGroups
              -- For use with MultiError trait
              if type component['fail'] == 'function' and component['hasErrors']
                component.fail()
              -- Disconnect outputs if still connected,
              -- this also indicates them as resolved if pending
              outputs = if table.getn(outPorts) == 1 then port: outs else outs
              disconnect = false
              if table.getn(component['disconnectQ']) > 0
                _.pop component['disconnectQ']
                disconnect = true
              for name, out in outputs
                for i in whenDoneGroups
                  if config['forwardGroups'] and config['async']
                    out.endGroup()
                out.disconnect() if disconnect
                out.done() if config.async or config['StreamSender']
              if type(component['afterProcess']) == 'function'
                component.afterProcess err or component.hasErrors, outs

            -- Before hook
            if type(component.beforeProcess) == 'function'
              component.beforeProcess outs

            -- Group forwarding
            if config['forwardGroups'] and config['async']
              if table.getn(outPorts) == 1
                outs.beginGroup g for g in groups
              else
                for name, out in outs
                  out.beginGroup g for g in groups

            -- Enforce MultiError with WirePattern (for group forwarding)
            MultiError component, config['name'], config['error'], groups

            -- Call the proc function
            if config['async']
              postpone = ->
              resume = ->
              postponedToQ = false
              task = ->
                proc.call component, data, groups, outs, whenDone, postpone, resume
              postpone = (backToQueue = true) ->
                postponedToQ = backToQueue
                if backToQueue
                  _.push component['taskQ'], task
              resume = ->
                if postponedToQ then resumeTaskQ() else task()
            else
              task = ->
                proc.call component, data, groups, outs
                whenDone()
            _.push component['taskQ'], task
            resumeTaskQ()

            -- Call the garbage collector
            gc()

  -- Overload shutdown method to clean WirePattern state
  baseShutdown = component['shutdown']
  component['shutdown'] = ->
    baseShutdown.call component
    component['groupedData'] = {}
    component['groupedGroups'] = {}
    component['outputQ'] = {}
    component['disconnectData'] = {}
    component['disconnectQ'] = {}
    component['taskQ'] = {}
    component['params'] = {}
    component['completeParams'] = {}
    component['receivedParams'] = {}
    component['defaultsSent'] = false
    component['groupBuffers'] = {}
    component['keyBuffers'] = {}
    component['gcTimestamps'] = {}
    component['gcCounter'] = 0

  -- Make it chainable or usable at the end of getComponent()
  return component

-- Alias for compatibility with 0.5.3
GroupedInput = WirePattern


-- `CustomError` returns an `Error` object carrying additional properties.
CustomError = (message, options) ->
  err = error message
  return CustomizeError err, options

-- `CustomizeError` sets additional options for an `Error` object.
CustomizeError = (err, options) ->
  for key in options
    continue if _.contains(options, key) == false
    err[key] = options[key]
  return err


-- `MultiError` simplifies throwing and handling multiple error objects
-- during a single component activation.
--
-- `group` is an optional group ID which will be used to wrap all error
-- packets emitted by the component.
MultiError = (component, group = '', errorPort = 'error', forwardedGroups = {}) ->
  component['hasErrors'] = false
  component['errors'] = {}

  -- Override component.error to support group information
  component['error'] = (e, groups = {}) ->
    _.push component.errors
      err: e
      groups: _.concat(forwardedGroups, groups)
    component['hasErrors'] = true

  -- Fail method should be called to terminate process immediately
  -- or to flush error packets.
  component['fail'] = (e = nil, groups = {}) ->
    component.error e, groups if e
    return unless component['hasErrors']
    return unless  _.contains component['outPorts'], errorPort
    return unless component['outPorts'][errorPort]\isAttached()
    component['outPorts'][errorPort]\beginGroup group if group
    for error in component['errors']
      component['outPorts'][errorPort]\beginGroup grp for grp in error['groups']
      component['outPorts'][errorPort]\send error['err']
      component['outPorts'][errorPort]\endGroup() for grp in error['groups']
    component['outPorts'][errorPort]\endGroup() if group
    component['outPorts'][errorPort]\disconnect()
    -- Clean the status for next activation
    component['hasErrors'] = false
    component['errors'] = {}

  -- Overload shutdown method to clear errors
  baseShutdown = component['shutdown']
  component['shutdown'] = ->
    baseShutdown.call component
    component['hasErrors'] = false
    component['errors'] = {}

  return component
