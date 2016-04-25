--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license


_ = require "moses"
internalSocket = require "InternalSocket"
graph = require "Graph"
EventEmitter = require 'events'
platform = require 'Platform'
cron = require 'cron'
require 'splice'
Error = require "Error"
Allen = require "Allen"
Allen.import()
--require 'indexOf'
componentLoader = require 'ComponentLoader'

exports = {}
--module "Streams", package.seeall

---- The MoonFlo network coordinator
--
--MoonFlo networks consist of processes connected to each other
--via sockets attached from outports to inports.
--
--The role of the network coordinator is to take a graph and
--instantiate all the necessary processes from the designated
--components, attach sockets between them, and handle the sending
--of Initial Information Packets.
class Network extends EventEmitter
  --Processes contains all the instantiated components for this network
  processes: {}
  --Connections contains all the socket connections in the network
  connections: {}
  --Initials contains all Initial Information Packets (IIPs)
  initials: {}
  --Container to hold sockets that will be sending default data.
  defaults: {}
  --The Graph this network is instantiated with
  graph: nil
  --Start-up timestamp for the network, used for calculating uptime
  startupDate: nil
  portBuffer: {}

  --All MoonFlo networks are instantiated with a graph. Upon instantiation
  --they will load all the needed components, instantiate them, and
  --set up the defined connections and IIPs.
  --
  --The network will also listen to graph changes and modify itself
  --accordingly, including removing connections, adding new nodes,
  --and sending new IIPs.
  new: (graph, @options = {}) =>
    @processes = {}
    @connections = {}
    @initials = {}
    @nextInitials = {}
    @defaults = {}
    @graph = graph
    @started = false
    @debug = true
    @connectionCount = 0

    --On Node.js we default the baseDir for component loading to
    --the current working directory
    unless platform.isBrowser()
      @baseDir = graph.baseDir or process.cwd()
    --On browser we default the baseDir to the Component loading
    --root
    else
      @baseDir = graph.baseDir or '/'

    --As most MoonFlo networks are long-running processes, the
    --network coordinator marks down the start-up time. This
    --way we can calculate the uptime of the network.
    @startupDate = nil

    --Initialize a Component Loader for the network
    if graph.componentLoader
      @loader = graph.componentLoader
    else
      @loader =   componentLoader.ComponentLoader @baseDir, @options

  --The uptime of the network is the current time minus the start-up
  --time, in seconds.
  uptime: =>
    return 0 unless @startupDate
    os.time() - @startupDate

  --Emit a 'start' event on the first connection, and 'end' event when
  --last connection has been closed
  increaseConnections: =>
    if @connectionCount == 0
      --First connection opened, execution has now started
      @setStarted true
    @connectionCount += 1
  decreaseConnections: =>
    @connectionCount -=1
    return if @connectionCount
    --Last connection closed, execution has now ended
    --We do this in debounced way in case there is an in-flight operation still
    unless @debouncedEnd
      @debouncedEnd = _.debounce => return if @connectionCount @setStarted false, 50  --TODO: find alternative to _.debounce currently not available in moses
    do @debouncedEnd

  ---- Loading components
  --
  --Components can be passed to the MoonFlo network in two ways:
  --
  --* As direct, instantiated JavaScript objects
  --* As filenames
  load: (component, metadata, callback) =>
    @loader.load component, callback, metadata

  ---- Add a process to the network
  --
  --Processes can be added to a network at either start-up time
  --or later. The processes are added with a node definition object
  --that includes the following properties:
  --
  --* `id`: Identifier of the process in the network. Typically a string
  --* `component`: Filename or path of a MoonFlo component, or a component instance object
  addNode: (node, callback) =>
    --Processes are treated as singletons by their identifier. If
    --we already have a process with the given ID, return that.
    if @processes[node.id]
      callback nil, @processes[node.id] if callback
      return

    process =
      id: node.id

    --No component defined, just register the process but don't start.
    unless node.component
      @processes[process.id] = process
      callback nil, process if callback
      return

    --Load the component for the process.
    @load node.component, node.metadata, (err, instance) =>
      return callback err if err
      instance.nodeId = node.id
      process.component = instance

      --Inform the ports of the node name
      for name, port in pairs(process['component']['inPorts'])
        continue if not port or type (port) == 'function' or not port.canAttach
        port.node = node.id
        port.nodeInstance = instance
        port.name = name

      for name, port in pairs(process['component']['outPorts'])
        continue if not port or type(port) == 'function' or not port.canAttach
        port.node = node.id
        port.nodeInstance = instance
        port.name = name

      @subscribeSubgraph process if instance.isSubgraph()

      @subscribeNode process

      --Store and return the process instance
      @processes[process.id] = process
      callback nil, process if callback

  removeNode: (node, callback) =>
    unless @processes[node.id]
      return callback   Error "Node #{node.id} not found"
    @processes[node.id].component.shutdown()
    delete @processes[node.id]
    callback nil if callback

  renameNode: (oldId,  Id, callback) =>
    process = @getNode oldId
    return callback   Error "Process #{oldId} not found" unless process

    --Inform the process of its ID
    process.id = newId

    --Inform the ports of the node name
    for name, port in pairs process['component']['inPorts']
      port.node = newId
    for name, port in pairs process['component']['outPorts']
      port.node = newId

    @processes[newId] = process
    delete @processes[oldId]
    callback nil if callback

  --Get process by its ID.
  getNode: (id) =>
    @processes[id]

  connect: (done = ->) =>
    --Wrap the future which will be called when done in a function and return
    --it
    callStack = 0
    serialize = (next, add) =>
      (type) =>
        --Add either a Node, an Initial, or an Edge and move on to the next one
        --when done
        @["add#{type}"] add, (err) ->
          print err if err
          return done err if err
          callStack +=1
          if callStack % 100 == 0
            cron.after 0, ()=> next type
            --setTimeout -> next type, 0
            return
          next type

    --Subscribe to graph changes when everything else is done
    subscribeGraph = =>
      @subscribeGraph()
      done()

    --Serialize default socket creation then call callback when done
    setDefaults = _.reduceRight @graph.nodes, serialize, subscribeGraph

    --Serialize initializers then call defaults.
    initializers = _.reduceRight @graph.initializers, serialize, -> setDefaults "Defaults"

    --Serialize edge creators then call the initializers.
    edges = _.reduceRight @graph.edges, serialize, -> initializers "Initial"

    --Serialize node creators then call the edge creators
    nodes = _.reduceRight @graph.nodes, serialize, -> edges "Edge"
    --Start with node creators
    nodes "Node"

  connectPort: (socket, process, port, index, inbound) ->
    if inbound
      socket.to =
        process: process
        port: port
        index: index

      unless process['component']['inPorts'] and process['component']['inPorts'][port]
        Error "No inport '#{port}' defined in process #{process.id} (#{socket.getId()})"
        return
      if process['component']['inPorts'][port].isAddressable()
        return process['component']['inPorts'][port].attach socket, index
      return process['component']['inPorts'][port].attach socket

    socket.from =
      process: process
      port: port
      index: index

    unless process['component']['outPorts'] and process['component']['outPorts'][port]
      Error "No outport '#{port}' defined in process #{process.id} (#{socket.getId()})"
      return

    if process['component']['outPorts'][port].isAddressable()
      return process['component']['outPorts'][port].attach socket, index
    process['component']['outPorts'][port].attach socket

  subscribeGraph: =>
    --A MoonFlo graph may change after network initialization.
    --For this, the network subscribes to the change events from
    --the graph.
    --
    --In graph we talk about nodes and edges. Nodes correspond
    --to MoonFlo processes, and edges to connections between them.
    graphOps = {}
    processing = false
    registerOp = (op, details) ->
      _.push graphOps,
        op: op
        details: details
    processOps = (err) =>
      if err
        Error err if table.getn(@listeners('process-error')) == 0
        @emit 'process-error', err

      unless table.getn graphOps
        processing = false
        return
      processing = true
      op = _.pop graphOps
      cb = processOps
      switch op.op
        when 'renameNode'
          @renameNode op.details.from, op.details.to, cb
        else
          @[op.op] op.details, cb

    @graph.on 'addNode', (node) =>
      registerOp 'addNode', node
      do processOps unless processing
    @graph.on 'removeNode', (node) =>
      registerOp 'removeNode', node
      do processOps unless processing
    @graph.on 'renameNode', (oldId, newId) =>
      registerOp 'renameNode',
        from: oldId
        to: newId
      do processOps unless processing
    @graph.on 'addEdge', (edge) =>
      registerOp 'addEdge', edge
      do processOps unless processing
    @graph.on 'removeEdge', (edge) =>
      registerOp 'removeEdge', edge
      do processOps unless processing
    @graph.on 'addInitial', (iip) =>
      registerOp 'addInitial', iip
      do processOps unless processing
    @graph.on 'removeInitial', (iip) =>
      registerOp 'removeInitial', iip
      do processOps unless processing

  subscribeSubgraph: (node) =>
    unless node['component']\isReady()
      node['component']\once 'ready', =>
        @subscribeSubgraph node
      return

    return unless node['component']['network']

    node['component']['network']\setDebug @debug

    emitSub = (_type, data) =>
      if _type == 'process-error' and table.getn(@listeners('process-error')) == 0
        Error data
      do @increaseConnections if _type == 'connect'
      do @decreaseConnections if _type == 'disconnect'
      data = {} unless data
      if data['subgraph']
        --unless data['subgraph'].unshift
          --data.subgraph = {data.subgraph}
        data.subgraph = table.insert data['subgraph'], 1, node['id']
      else
        data.subgraph = {node.id}
      @emit type, data

    node['component']['network']\on 'connect', (data) -> emitSub 'connect', data
    node['component']['network']\on 'begingroup', (data) -> emitSub 'begingroup', data
    node['component']['network']\on 'data', (data) -> emitSub 'data', data
    node['component']['network']\on 'endgroup', (data) -> emitSub 'endgroup', data
    node['component']['network']\on 'disconnect', (data) -> emitSub 'disconnect', data
    node['component']['network']\on 'process-error', (data) ->
      emitSub 'process-error', data

  --Subscribe to events from all connected sockets and re-emit them
  subscribeSocket: (socket) =>
    socket.on 'connect', =>
      do @increaseConnections
      @emit 'connect',
        id: socket.getId()
        socket: socket
        metadata: socket.metadata
    socket.on 'begingroup', (group) =>
      @emit 'begingroup',
        id: socket.getId()
        socket: socket
        group: group
        metadata: socket.metadata
    socket.on 'data', (data) =>
      @emit 'data',
        id: socket.getId()
        socket: socket
        data: data
        metadata: socket.metadata
    socket.on 'endgroup', (group) =>
      @emit 'endgroup',
        id: socket.getId()
        socket: socket
        group: group
        metadata: socket.metadata
    socket.on 'disconnect', =>
      do @decreaseConnections
      @emit 'disconnect',
        id: socket.getId()
        socket: socket
        metadata: socket.metadata
    socket.on 'error', (event) =>
      error event if table.getn(@listeners('process-error')) == 0
      @emit 'process-error', event

  subscribeNode: (node) =>
    return unless node['component'].getIcon
    node['component']\on 'icon', =>
      @emit 'icon',
        id: node.id
        icon: node['component']\getIcon()

  addEdge: (edge, callback) =>
    socket = internalSocket.createSocket edge['metadata']
    socket.setDebug @debug
    edge = json.decode edge
    frm = @getNode edge['from']['node']   --from is a moonscript keyword so we use frm
    unless frm
      return callback   Error "No process defined for outbound node #{edge['from']['node']}"
    unless frm.component
      return callback   Error "No component defined for outbound node #{edge['from']['node']}"
    unless frm['component'].isReady()
      frm['component'].once "ready", =>
        @addEdge edge, callback

      return

    to = @getNode edge['to']['node']
    unless to
      return callback   Error "No process defined for inbound node #{edge['to']['node']}"
    unless to['component']
      return callback   Error "No component defined for inbound node #{edge['to']['node']}"
    unless to['component'].isReady()
      to['component'].once "ready", =>
        @addEdge edge, callback

      return

    --Subscribe to events from the socket
    @subscribeSocket socket

    @connectPort socket, to, edge['to']['port'], edge['to']['index'], true
    @connectPort socket, frm, edge['from']['port'], edge['from']['index'], false

    _.push @connections, socket
    callback() if callback

  removeEdge: (edge, callback) =>
    for connection in @connections
      continue unless connection
      continue unless edge['to']['node'] == connection['to']['process']['id'] and edge['to']['port'] == connection['to']['port']
      connection['to']['process']['component']['inPorts'][connection['to']['port']].detach connection
      if edge['from']['node']
        if connection.from and edge['from']['node'] == connection['from']['process']['id'] and edge['from']['port'] == connection['from']['port']
          connection['from']['process']['component']['outPorts'][connection['from']['port']].detach connection
      splice @connections, _.indexOf(@connections, connection), 1
      do callback if callback

  addDefaults: (node, callback) =>

    process = @processes[node.id]

    unless process['component']\isReady()
      process['component']\setMaxListeners 0 if process['component']\setMaxListeners
      process['component']\once "ready", =>
        @addDefaults process, callback
      return

    for key, port in pairs process['component']['inPorts']['ports']
      --Attach a socket to any defaulted inPorts as long as they aren't already attached.
      --TODO: hasDefault existence check is for backwards compatibility, clean
      --      up when legacy ports are removed.
      if type(port['hasDefault']) == 'function' and port.hasDefault() and not port.isAttached()
        socket = internalSocket.createSocket()
        socket\setDebug @debug

        --Subscribe to events from the socket
        @subscribeSocket socket

        @connectPort socket, process, key, undefined, true

        _.push @connections, socket

        _.push @defaults, socket

    callback() if callback

  addInitial: (initializer, callback) =>
    socket = internalSocket\createSocket initializer['metadata']
    socket\setDebug @debug

    --Subscribe to events from the socket
    @subscribeSocket socket

    to = @getNode initializer['to']['node']
    unless to
      return callback  Error "No process defined for inbound node #{initializer.to.node}"

    unless to['component'].isReady() or to['component']['inPorts'][initializer['to']['port']]
      to['component'].setMaxListeners 0 if to['component'].setMaxListeners
      to['component'].once "ready", =>
        @addInitial initializer, callback
      return

    @connectPort socket, to, initializer['to']['port'], initializer['to']['index'], true

    _.push @connections, socket

    init =
      socket: socket
      data: initializer['from']['data']
    _.push @initials, init
    _.push @nextInitials, init

    do @sendInitials if @isStarted()

    callback() if callback

  removeInitial: (initializer, callback) =>
    for connection in @connections
      continue unless connection
      continue unless initializer['to']['node'] == connection['to']['process']['id'] and initializer['to']['port'] == connection['to']['port']
      connection['to']['process']['component']['inPorts'][connection['to']['port']].detach connection
      splice @connections, _.indexOf(@connections, connection), 1

      for init in @initials
        continue unless init
        continue unless init['socket'] == connection
        splice @initials, _.indexOf(@initials, init), 1
      for init in @nextInitials
        continue unless init
        continue unless init.socket == connection
        splice @nextInitials, _.indexOf(@nextInitials, init), 1

    do callback if callback

  sendInitial: (initial) =>
    initial['socket']\connect()
    initial['socket']\send initial.data
    initial['socket']\disconnect()

  sendInitials: (callback) =>
    unless callback
      callback = ->

    send = =>
      @sendInitial initial for initial in @initials
      @initials = {}
      do callback

    if type(process) != 'nil' and process['execPath'] and _.indexOf(process['execPath'], 'node') != -1
      --nextTick is faster on Node.js
      process\nextTick send
    else
      cron.after(0, send)

  isStarted: =>
    @started

  isRunning: =>
    return false unless @started
    @connectionCount > 0

  startComponents: (callback) =>
    unless callback
      callback = ->

    --Perform any startup routines necessary for every component.
    for id, process in pairs @processes
      process['component']\start()
    do callback

  sendDefaults: (callback) =>
    unless callback
      callback = ->

    return callback() unless table.getn @defaults

    for socket in @defaults
      --Don't send defaults if more than one socket is present on the port.
      --This case should only happen when a subgraph is created as a component
      --as its network is instantiated and its inputs are serialized before
      --a socket is attached from the "parent" graph.
      continue unless table.getn(socket['to']['process']['component']['inPorts'][socket['to']['port']]['sockets']) == 1
      socket\connect()
      socket\send()
      socket\disconnect()

    do callback

  start: (callback) ->
    unless callback
      callback = ->

    do @stop if @started
    @initials = _.slice @nextInitials, 0
    @startComponents (err) =>
      return callback err if err
      @sendInitials (err) =>
        return callback err if err
        @sendDefaults (err) =>
          return callback err if err
          @setStarted true
          callback nil

  stop: =>
    --Disconnect all connections
    for connection in @connections
      continue unless connection.isConnected()
      connection.disconnect()
    --Tell processes to shut down
    for id, process in pairs @processes
      process['component']\shutdown()
    @setStarted false

  setStarted: (started) =>
    return if @started == started
    unless started
      --Ending the execution
      @started = false
      @emit 'end',
        start: @startupDate
        end: os.time()
        uptime: @uptime()
      return

    --Starting the execution
    @startupDate =   os.time() unless @startupDate
    @started = true
    @emit 'start',
      start: @startupDate

  getDebug: () =>
    @debug

  setDebug: (active) =>
    return if active == @debug
    @debug = active

    for socket in @connections
      socket.setDebug active
    for processId, process in pairs @processes
      instance = process['component']
      instance['network']\setDebug active if instance.isSubgraph()

--exports.Network = Network
exports['Network'] = Network

return exports
