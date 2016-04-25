--     MoonFlo - Flow-Based Programming for MoonScript
--     (c) 2014-2015 TheGrid (Rituwall Inc.)
--      @Author Damilare Akinlaja, 2016
--     MoonFlo may be freely distributed under the MIT license
EventEmitter = require 'events'

clone = require('Utils').clone
platform = require 'Platform'
splice = require 'splice'
_ = require "moses"
json = require "cjson"
Allen = require "Allen"
Allen.import()

expots = {}

-- This class represents an abstract NoFlo graph containing nodes
-- connected to each other with edges.
--
-- These graphs can be used for visualization and sketching, but
-- also are the way to start a NoFlo network.
class Graph extends EventEmitter
  name: ''
  properties: {}
  nodes: {}
  edges: {}
  initializers: {}
  exports: {}
  inports: {}
  outports: {}
  groups: {}

  -- ---- Creating new graphs
  --
  -- Graphs are created by simply instantiating the Graph class
  -- and giving it a name:
  --
  --     myGraph = new Graph 'My very cool graph'
  new: (@name = '') =>
    @properties = {}
    @nodes = {}
    @edges = {}
    @initializers = {}
    @exports = {}
    @inports = {}
    @outports = {}
    @groups = {}
    @transaction =
      id: nil
      depth: 0

  -- ---- Group graph changes into transactions
  --
  -- If no transaction is explicitly opened, each call to
  -- the graph API will implicitly create a transaction for that change
  startTransaction: (id, metadata) ->
    if @transaction['id']
      error("Nested transactions not supported")

    @transaction['id'] = id
    @transaction['depth'] = 1
    @emit 'startTransaction', id, metadata

  endTransaction: (id, metadata) ->
    if not @transaction['id']
      error("Attempted to end non-existing transaction")

    @transaction['id'] = nil
    @transaction['depth'] = 0
    @emit 'endTransaction', id, metadata

  checkTransactionStart: () ->
    if not @transaction['id']
      @startTransaction 'implicit'
    else if @transaction['id'] == 'implicit'
      @transaction['depth'] += 1

  checkTransactionEnd: () ->
    if @transaction['id'] == 'implicit'
      @transaction['depth'] -= 1
    if @transaction['depth'] == 0
      @endTransaction 'implicit'

  -- ---- Modifying Graph properties
  --
  -- This method allows changing properties of the graph.
  setProperties: (properties) =>
    @checkTransactionStart()
    before = clone @properties
    for item in properties
      @properties[item] = properties[item]
    @emit 'changeProperties', @properties, before
    @checkTransactionEnd()

  -- ---- Exporting a port from subgraph
  --
  -- This allows subgraphs to expose a cleaner API by having reasonably
  -- named ports shown instead of all the free ports of the graph
  --
  -- The ports exported using this way are ambiguous in their direciton. Use
  -- `addInport` or `addOutport` instead to disambiguate.
  addExport: (publicPort, nodeKey, portKey, metadata = {x:0,y:0}) =>
    -- Check that node exists
    return unless @getNode nodeKey

    @checkTransactionStart()

    exported =
      public: string.lower(publicPort)
      process: nodeKey
      port: string.lower portKey
      metadata: metadata
    _.push @exports, exported
    @emit 'addExport', exported

    @checkTransactionEnd()

  removeExport: (publicPort) =>
    publicPort = string.lower publicPort
    found = nil
    for exported, idx in @exports
      found = exported if exported['public'] == publicPort

    return unless found
    @checkTransactionStart()
    splice @exports, _.indexOf(@exports, found), 1
    @emit 'removeExport', found
    @checkTransactionEnd()

  addInport: (publicPort, nodeKey, portKey, metadata) =>
    -- Check that node exists
    return unless @getNode nodeKey

    publicPort = string.lower publicPort
    @checkTransactionStart()
    @inports[publicPort] =
      process: nodeKey
      port: @exports portKey
      metadata: metadata
    @emit 'addInport', publicPort, @inports[publicPort]
    @checkTransactionEnd()

  removeInport: (publicPort) =>
    publicPort = @exports publicPort
    return unless @inports[publicPort]

    @checkTransactionStart()
    port = @inports[publicPort]
    @setInportMetadata publicPort, {}
    table.remove @inports , publicPort
    @emit 'removeInport', publicPort, port
    @checkTransactionEnd()

  renameInport: (oldPort, newPort) =>
    oldPort = string.lower oldPort
    newPort = string.lower newPort
    return unless @inports[oldPort]

    @checkTransactionStart()
    @inports[newPort] = @inports[oldPort]
    table.remove @inports, oldPort
    @emit 'renameInport', oldPort, newPort
    @checkTransactionEnd()

  setInportMetadata: (publicPort, metadata) =>
    publicPort = string.lower publicPort
    return unless @inports[publicPort]

    @checkTransactionStart()
    before = clone @inports[publicPort]['metadata']
    @inports[publicPort]['metadata'] = {} unless @inports[publicPort]['metadata']
    for item in metadata
      if metadata[item] == nil
        @inports[publicPort]['metadata'][item] = metadata[item]
      else
        table.remove @inports[publicPort]['metadata'], item
    @emit 'changeInport', publicPort, @inports[publicPort], before
    @checkTransactionEnd()

  addOutport: (publicPort, nodeKey, portKey, metadata) =>
    -- Check that node exists
    return unless @getNode nodeKey

    publicPort = string.lower publicPort
    @checkTransactionStart()
    @outports[publicPort] =
      process: nodeKey
      port: string.lower portKey
      metadata: metadata
    @emit 'addOutport', publicPort, @outports[publicPort]

    @checkTransactionEnd()

  removeOutport: (publicPort) =>
    publicPort = string.lower publicPort
    return unless @outports[publicPort]

    @checkTransactionStart()

    port = @outports[publicPort]
    @setOutportMetadata publicPort, {}
    table.remove @outports, publicPort
    @emit 'removeOutport', publicPort, port

    @checkTransactionEnd()

  renameOutport: (oldPort, newPort) =>
    oldPort = string.lower oldPort
    newPort = string.lower newPort
    return unless @outports[oldPort]

    @checkTransactionStart()
    @outports[newPort] = @outports[oldPort]
    table.remove @outports, oldPort
    @emit 'renameOutport', oldPort, newPort
    @checkTransactionEnd()

  setOutportMetadata: (publicPort, metadata) =>
    publicPort = string.lower publicPort
    return unless @outports[publicPort]

    @checkTransactionStart()
    before = clone @outports[publicPort]['metadata']
    @outports[publicPort]['metadata'] = {} unless @outports[publicPort]['metadata']
    for item in metadata
      if metadata[item] == nil
        @outports[publicPort].metadata[item] = metadata[item]
      else
        table.remove @outports[publicPort]['metadata'], item
    @emit 'changeOutport', publicPort, @outports[publicPort], before
    @checkTransactionEnd()

  -- ---- Grouping nodes in a graph
  --
  addGroup: (group, nodes, metadata) =>
    @checkTransactionStart()

    g =
      name: group
      nodes: nodes
      metadata: metadata
    _.push @groups, g
    @emit 'addGroup', g

    @checkTransactionEnd()

  renameGroup: (oldName, newName) ->
    @checkTransactionStart()
    for group in @groups
      continue unless group
      continue unless group['name'] == oldName
      group['name'] = newName
      @emit 'renameGroup', oldName, newName
    @checkTransactionEnd()

  removeGroup: (groupName) ->
    @checkTransactionStart()

    for group in @groups
      continue unless group
      continue unless group['name'] == groupName
      @setGroupMetadata group['name'], {}
      splice @groups, _.indexOf(@groups, group), 1
      @emit 'removeGroup', group

    @checkTransactionEnd()

  setGroupMetadata: (groupName, metadata) =>
    @checkTransactionStart()
    for group in @groups
      continue unless group
      continue unless group['name'] == groupName
      before = clone group['metadata']
      for item in metadata
        if metadata[item] == nil
          group['metadata'][item] = metadata[item]
        else
          table.remove group['metadata'], item
      @emit 'changeGroup', group, before
    @checkTransactionEnd()

  -- ---- Adding a node to the graph
  --
  -- Nodes are identified by an ID unique to the graph. Additionally,
  -- a node may contain information on what NoFlo component it is and
  -- possible display coordinates.
  --
  -- For example:
  --
  --     myGraph.addNode 'Read, 'ReadFile',
  --       x: 91
  --       y: 154
  --
  -- Addition of a node will emit the `addNode` event.
  addNode: (id, component, metadata) =>
    @checkTransactionStart()

    metadata = {} unless metadata
    node =
      id: id
      component: component
      metadata: metadata
    _.push @nodes, node
    @emit 'addNode', node

    @checkTransactionEnd()
    node

  -- ---- Removing a node from the graph
  --
  -- Existing nodes can be removed from a graph by their ID. This
  -- will remove the node and also remove all edges connected to it.
  --
  --     myGraph.removeNode 'Read'
  --
  -- Once the node has been removed, the `removeNode` event will be
  -- emitted.
  removeNode: (id) =>
    node = @getNode id
    return unless node

    @checkTransactionStart()

    toRemove = {}
    for edge in @edges
      if (edge['from']['node'] == node['id']) or (edge['to']['node'] == node['id'])
        _.push toRemove, edge
    for edge in toRemove
      @removeEdge edge['from']['node'], edge['from']['port'], edge['to']['node'], edge['to']['port']

    toRemove = {}
    for initializer in @initializers
      if initializer['to']['node'] == node['id']
        _.push initializer, toRemove
    for initializer in toRemove
      @removeInitial initializer['to']['node'], initializer['to']['port']

    toRemove = {}
    for exported in @exports
      if string.lower(id) == exported['process']
        _.push toRemove, exported
    for exported in toRemove
      @removeExport exported['public']

    toRemove = {}
    for pub in @inports
      priv = @inports[pub]
      if priv['process'] == id
        _.push toRemove, pub
    for pub in toRemove
      @removeInport pub

    toRemove = {}
    for pub in @outports
      priv = @outports[pub]
      if priv['process'] == id
        _.push toRemove, pub
    for pub in toRemove
      @removeOutport pub

    for group in @groups
      continue unless group
      index = _.indexOf(group['nodes'], id)
      continue if index == -1
      splice group['nodes'], index, 1

    @setNodeMetadata id, {}

    if -1 != _.indexOf(@nodes, node)
      splice @nodes, _.indexOf(@nodes, node), 1

    @emit 'removeNode', node

    @checkTransactionEnd()

  -- ---- Getting a node
  --
  -- Nodes objects can be retrieved from the graph by their ID:
  --
  --     myNode = myGraph.getNode 'Read'
  getNode: (id) =>
    for node in @nodes
      continue unless node
      return node if node['id'] == id
    return nil

  -- ---- Renaming a node
  --
  -- Nodes IDs can be changed by calling this method.
  renameNode: (oldId, newId) ->
    @checkTransactionStart()

    node = @getNode oldId
    return unless node
    node['id'] = newId

    for edge in @edges
      continue unless edge
      if edge['from']['node'] == oldId
        edge['from']['node'] = newId
      if edge['to']['node'] == oldId
        edge['to']['node'] = newId

    for iip in @initializers
      continue unless iip
      if iip['to']['node'] == oldId
        iip['to']['node'] = newId

    for pub in @inports
      priv = @inports[pub]
      if priv['process'] == oldId
        priv['process'] = newId
    for pub in @outports
      priv = @outports[pub]
      if priv['process'] == oldId
        priv['process'] = newId
    for exported in @exports
      if exported['process'] == oldId
        exported['process'] = newId

    for group in @groups
      continue unless group
      index = _.indexOf(group['nodes'], oldId)
      continue if index == -1
      group['nodes'][index] = newId

    @emit 'renameNode', oldId, newId
    @checkTransactionEnd()

  -- ---- Changing a node's metadata
  --
  -- Node metadata can be set or changed by calling this method.
  setNodeMetadata: (id, metadata) =>
    node = @getNode id
    return unless node

    @checkTransactionStart()

    before = clone node['metadata']
    node.metadata = {} unless node['metadata']

    for item in metadata
      val = metadata[item]
      if val != nil
        node['metadata'][item] = val
      else
        table.remove node['metadata'], item

    @emit 'changeNode', node, before
    @checkTransactionEnd()

  -- ---- Connecting nodes
  --
  -- Nodes can be connected by adding edges between a node's outport
  -- and another node's inport:
  --
  --     myGraph.addEdge 'Read', 'out', 'Display', 'in'
  --     myGraph.addEdgeIndex 'Read', 'out', nil, 'Display', 'in', 2
  --
  -- Adding an edge will emit the `addEdge` event.
  addEdge: (outNode, outPort, inNode, inPort, metadata = {}) =>
    outPort = string.lower outPort
    inPort = string.lower inPort
    for edge in @edges
      -- don't add a duplicate edge
      return if (edge['from']['node'] == outNode and edge['from']['port'] == outPort and edge['to']['node'] == inNode and edge['to']['port'] == inPort)
    return unless @getNode outNode
    return unless @getNode inNode

    @checkTransactionStart()

    edge =
      from:
        node: outNode
        port: outPort
      to:
        node: inNode
        port: inPort
      metadata: metadata
    _.push @edges, edge
    @emit 'addEdge', edge

    @checkTransactionEnd()
    edge

  -- Adding an edge will emit the `addEdge` event.
  addEdgeIndex: (outNode, outPort, outIndex, inNode, inPort, inIndex, metadata = {}) =>
    return unless @getNode outNode
    return unless @getNode inNode

    outPort = string.lower outPort
    inPort = string.lower inPort

    inIndex = undefined if inIndex == nil
    outIndex = undefined if outIndex == nil
    metadata = {} unless metadata

    @checkTransactionStart()

    edge =
      from:
        node: outNode
        port: outPort
        index: outIndex
      to:
        node: inNode
        port: inPort
        index: inIndex
      metadata: metadata
    _.push @edges, edge
    @emit 'addEdge', edge

    @checkTransactionEnd()
    edge

  -- ---- Disconnected nodes
  --
  -- Connections between nodes can be removed by providing the
  -- nodes and ports to disconnect.
  --
  --     myGraph.removeEdge 'Display', 'out', 'Foo', 'in'
  --
  -- Removing a connection will emit the `removeEdge` event.
  removeEdge: (node, port, node2, port2) =>
    @checkTransactionStart()
    port = string.lower port
    port2 =  string.lower port2
    toRemove = {}
    toKeep = {}
    if node2 and port2
      for edge,index in pairs @edges
        if edge['from']['node'] == node and edge['from']['port'] == port and edge['to']['node'] == node2 and edge['to']['port'] == port2
          @setEdgeMetadata edge['from']['node'], edge['from']['port'], edge['to']['node'], edge['to']['port'], {}
          _.push toRemove, edge
        else
          _.push toKeep, edge
    else
      for edge,index in pairs @edges
        if (edge['from']['node'] == node and edge['from']['port'] == port) or (edge['to']['node'] == node and edge['to']['port'] == port)
          @setEdgeMetadata edge['from']['node'], edge['from']['port'], edge['to']['node'], edge['to']['port'], {}
          _.push toRemove, edge
        else
          _.push toKeep, edge

    @edges = toKeep
    for edge in toRemove
      @emit 'removeEdge', edge

    @checkTransactionEnd()

  -- ---- Getting an edge
  --
  -- Edge objects can be retrieved from the graph by the node and port IDs:
  --
  --     myEdge = myGraph.getEdge 'Read', 'out', 'Write', 'in'
  getEdge: (node, port, node2, port2) =>
    port = string.lower port
    port2 = string.lower port2
    for edge,index in pairs @edges
      continue unless edge
      if edge['from']['node'] == node and edge['from']['port'] == port
        if edge['to']['node'] == node2 and edge['to']['port'] == port2
          return edge
    return nil

  -- ---- Changing an edge's metadata
  --
  -- Edge metadata can be set or changed by calling this method.
  setEdgeMetadata: (node, port, node2, port2, metadata) =>
    edge = @getEdge node, port, node2, port2
    return unless edge

    @checkTransactionStart()
    before = clone edge['metadata']
    edge.metadata = {} unless edge['metadata']

    for item in metadata
      val = metadata[item]
      if val != nil
        edge.metadata[item] = val
      else
        table.remove edge['metadata'], item

    @emit 'changeEdge', edge, before
    @checkTransactionEnd()

  -- ---- Adding Initial Information Packets
  --
  -- Initial Information Packets (IIPs) can be used for sending data
  -- to specified node inports without a sending node instance.
  --
  -- IIPs are especially useful for sending configuration information
  -- to components at NoFlo network start-up time. This could include
  -- filenames to read, or network ports to listen to.
  --
  --     myGraph.addInitial 'somefile.txt', 'Read', 'source'
  --     myGraph.addInitialIndex 'somefile.txt', 'Read', 'source', 2
  --
  -- If inports are defined on the graph, IIPs can be applied calling
  -- the `addGraphInitial` or `addGraphInitialIndex` methods.
  --
  --     myGraph.addGraphInitial 'somefile.txt', 'file'
  --     myGraph.addGraphInitialIndex 'somefile.txt', 'file', 2
  --
  -- Adding an IIP will emit a `addInitial` event.
  addInitial: (data, node, port, metadata) =>
    return unless @getNode node

    port = string.lower port
    @checkTransactionStart()
    initializer =
      from:
        data: data
      to:
        node: node
        port: port
      metadata: metadata
    _.push @initializers, initializer
    @emit 'addInitial', initializer

    @checkTransactionEnd()
    initializer

  addInitialIndex: (data, node, port, index, metadata) =>
    return unless @getNode node
    index = nil if index == nil

    port = string.lower port
    @checkTransactionStart()
    initializer =
      from:
        data: data
      to:
        node: node
        port: port
        index: index
      metadata: metadata
    _.push @initializers, initializer
    @emit 'addInitial', initializer

    @checkTransactionEnd()
    initializer

  addGraphInitial: (data, node, metadata) =>
    inport = @inports[node]
    return unless inport
    @addInitial data, inport['process'], inport['port'], metadata

  addGraphInitialIndex: (data, node, index, metadata) =>
    inport = @inports[node]
    return unless inport
    @addInitialIndex data, inport['process'], inport['port'], index, metadata

  -- ---- Removing Initial Information Packets
  --
  -- IIPs can be removed by calling the `removeInitial` method.
  --
  --     myGraph.removeInitial 'Read', 'source'
  --
  -- If the IIP was applied via the `addGraphInitial` or
  -- `addGraphInitialIndex` functions, it can be removed using
  -- the `removeGraphInitial` method.
  --
  --     myGraph.removeGraphInitial 'file'
  --
  -- Remove an IIP will emit a `removeInitial` event.
  removeInitial: (node, port) =>
    port = string.lower port
    @checkTransactionStart()

    toRemove = {}
    toKeep = {}
    for edge, index in pairs @initializers
      if edge['to']['node'] == node and edge['to']['port'] == port
        _.push toRemove, edge
      else
        _.push toKeep, edge
    @initializers = toKeep
    for edge in toRemove
      @emit 'removeInitial', edge

    @checkTransactionEnd()

  removeGraphInitial: (node) =>
    inport = @inports[node]
    return unless inport
    @removeInitial inport['process'], inport['port']

  toDOT: ->
    cleanID = (id) =>
      id.replace /\s*/g, ""  --TODO: find Lua equivalent of regex replace
    cleanPort = (port) =>
      port.replace /\./g, "" --TODO: find Lua equivalent of regex replace

    dot = "digraph {\n"

    for node in @nodes
      dot += "    #{cleanID(node['id'])} [label=#{node['id']} shape=box]\n"

    for initializer, id in pairs @initializers
      if type(initializer['from']['data']) == 'function'
        data = 'Function'
      else
        data = initializer['from']['data']
      dot += "    data#{id} [label=\"'#{data}'\" shape=plaintext]\n"
      dot += "    data#{id} -> #{cleanID(initializer['to']['node'])}[headlabel=#{cleanPort(initializer['to']['port'])} labelfontcolor=blue labelfontsize=8.0]\n"

    for edge in @edges
      dot += "    #{cleanID(edge['from']['node'])} -> #{cleanID(edge['to']['node'])}[taillabel=#{cleanPort(edge['from']['port'])} headlabel=#{cleanPort(edge['to']['port'])} labelfontcolor=blue labelfontsize=8.0]\n"

    dot += "}"

    return dot

  toYUML: ->
    yuml = {}

    for initializer in @initializers
      _.push yuml, "(start)[#{initializer['to']['port']}]->(#{initializer['to']['node']})"

    for edge in @edges
      _.push yuml, "(#{edge['from']['node']})[#{edge['from']['port']}]->(#{edge['to']['node']})"
    _.concat yuml, ","

  toJSON: =>
    json =
      properties: {}
      inports: {}
      outports: {}
      groups: {}
      processes: {}
      connections: {}

    json['properties']['name'] = @name if @name
    for property in @properties
      value = @properties[property]
      json['properties'][property] = value

    for pub in @inports
      json['inports'][pub] = @inports[pub]
    for pub in @outports
      json['outports'][pub] = @outports[pub]

    -- Legacy exported ports
    for exported in @exports
      json['exports'] = {} unless json['exports']
      _.push json['exports'], exported

    for group in @groups
      groupData =
        name: group['name']
        nodes: group['nodes']
      if table.getn _.keys(group['metadata'])
        groupData['metadata'] = group['metadata']
      _.push json['groups'], groupData

    for node in @nodes
      json['processes'][node['id']] =
        component: node['component']
      if node['metadata']
        json['processes'][node['id']]['metadata'] = node['metadata']

    for edge in @edges
      connection =
        src:
          process: edge['from']['node']
          port: edge['from']['port']
          index: edge['from']['index']
        tgt:
          process: edge['to']['node']
          port: edge['to']['port']
          index: edge['to']['index']
      connection['metadata'] = edge['metadata'] if table.getn _.keys(edge['metadata'])
      _.push json['connections'], connection

    for initializer in @initializers
      json['connections']['push']
        data: initializer['from']['data']
        tgt:
          process: initializer['to']['node']
          port: initializer['to']['port']
          index: initializer['to']['index']

    json

  save: (file, callback) =>
    json = json.encode(@toJSON())--JSON.stringify @toJSON(), nil, 4
    file = io.open "#{file}.json", "w"
    file\write json
    file\close!
    callback file
    --require('fs').writeFile "#{file}.json", json, "utf-8", (err, data) ->
      --throw err if err
      --callback file

expots['Graph'] = Graph

expots['createGraph'] = (name) ->
  Graph name

expots['loadJSON'] = (definition, callback, metadata = {}) ->
  definition = json.decode definition if type(definition) == 'string'
  definition['properties'] = {} unless definition['properties']
  definition['processes'] = {} unless definition['processes']
  definition['connections'] = {} unless definition['connections']

  graph = Graph definition['properties']['name']

  graph\startTransaction 'loadJSON', metadata
  properties = {}
  for property in definition['properties']
    value = definition['properties'][property]
    continue if property == 'name'
    properties[property] = value
  graph\setProperties properties

  for id in definition['processes']
    def = definition['processes'][id]
    def['metadata'] = {} unless def['metadata']
    graph\addNode id, def['component'], def['metadata']

  for conn in definition['connections']
    metadata = if conn['metadata'] then conn['metadata'] else {}
    if conn['data'] != undefined
      if type(conn['tgt']['index']) == 'number'
        graph\addInitialIndex conn['data'], conn['tgt']['process'], string.lower (conn['tgt']['port']), conn['tgt']['index'], metadata
      else
        graph.addInitial conn['data'], conn['tgt']['process'], string.lower (conn['tgt']['port']), metadata
      continue
    if type(conn['src']['index']) == 'number' or type(conn['tgt']['index'] == 'number'
      graph\addEdgeIndex conn['src']['process'], string.lower (conn['src']['port']), conn['src']['index'], conn['tgt']['process'], string.lower(conn['tgt']['port']), conn['tgt']['index'], metadata
      continue
    graph\addEdge conn['src']['process'], string.lower(conn['src']['port']), conn['tgt']['process'], string.lower(conn['tgt']['port']), metadata

  if definition['exports'] and table.getn definition['exports']
    for exported in definition['exports']
      if exported['private']
        -- Translate legacy ports to new
        split = require "split"
        split = split(exported['private'],'.')
        continue unless table.getn(split) == 2
        processId = split[1]
        portId = split[2]

        -- Get properly cased process id
        for id in definition.processes
          if string.lower(id) == string.lower(processId)
            processId = id
      else
        processId = exported['process']
        portId = string.lower exported['port']
      graph\addExport exported['public'], processId, portId, exported['metadata']

  if definition['inports']
    for pub in definition['inports']
      priv = definition['inports'][pub]
      graph.addInport pub, priv['process'], string.lower(priv['port']), priv['metadata']
  if definition['outports']
    for pub in definition['outports']
      priv = definition['outports'][pub]
      graph.addOutport pub, priv['process'], string.lower(priv['port']), priv['metadata']

  if definition['groups']
    for group in definition['groups']
      if group['metadata']
        graph.addGroup group['name'], group['nodes'], group['metadata']
      else
        graph.addGroup group['name'], group['nodes'], {}

  graph.endTransaction 'loadJSON'

  callback nil, graph

expots['loadFBP'] = (fbpData, callback) ->
  --try
  definition, err = require('fbp').parse fbpData
    if err then return callback err
  --catch e
    --return callback e
  loadJSON definition, callback

expots['loadHTTP'] = (url, callback) ->
  req = XMLHttpRequest
  req.onreadystatechange = ->
    return unless req.readyState is 4
    unless req.status is 200
      return callback new Error "Failed to load #{url}: HTTP #{req.status}"
    callback nil, req.responseText
  req.open 'GET', url, true
  req.send()

expots['loadFile'] = (file, callback, metadata = {}) ->
  --if platform.isBrowser()
    --try
      -- Graph exposed via Component packaging
  definition, err = require file
    --catch e
      -- Graph available via HTTP
  if err
      loadHTTP file, (err, data) ->
        return callback err if err
        if _.pop(split(file,'.')) == 'fbp'
          return loadFBP data, callback, metadata
        definition =  data
        loadJSON definition, callback, metadata
      return
  loadJSON definition, callback, metadata
  return
  -- Node.js graph file
  file = io.open file, "r"
  data, err = file\read(*a)
  file\close!
  --callback data
  if err
    callback err
  --require('fs').readFile file, "utf-8", (err, data) ->
    --return callback err if err
  elseif data
    split = require "split"
    if _.pop(split(file,'.')) == 'fbp'
      return loadFBP data, callback

    definition = data
    loadJSON definition, callback

-- remove everything in the graph
resetGraph = (graph) ->

  -- Edges and similar first, to have control over the order
  -- If we'd do nodes first, it will implicitly delete edges
  -- Important to make journal transactions invertible
  for group in _.reverse(clone graph['groups'])
    graph\removeGroup group['name'] if group == nil
  for port in clone graph['outports']
    v = (clone graph['outports'])[port]
    graph\removeOutport port
  for port in clone graph['inports']
    v = (clone graph['inports'])[port]
    graph\removeInport port
  for exp in _.reverse(clone graph['exports'])
    graph\removeExport exp['public']
  -- XXX: does this actually nil the props??
  graph\setProperties {}
  for iip in _.reverse(clone graph['initializers'])
    graph\removeInitial iip['to']['node'], iip['to']['port']
  for edge in _.reverse(clone graph.edges)
    graph\removeEdge edge['from']['node'], edge['from']['port'], edge['to']['node'], edge['to']['port']
  for node in _.reverse(clone graph['nodes'])
    graph\removeNode node['id']

-- Note: Caller should create transaction
-- First removes everything in @base, before building it up to mirror @to
mergeResolveTheirsNaive = (base, to) =>
  resetGraph base

  for node in to['nodes']
    base\addNode node['id'], node['component'], node['metadata']
  for edge in to['edges']
    base\addEdge edge['from']['node'], edge['from']['port'], edge['to']['node'], edge['to']['port'], edge['metadata']
  for iip in to['initializers']
    base\addInitial iip['from']['data'], iip['to']['node'], iip['to']['port'], iip['metadata']
  for exp in to['exports']
    base\addExport exp['public'], exp['node'], exp['port'], exp['metadata']
  base\setProperties to['properties']
  for pub in to['inports']
    priv = to['inports'][pub]
    base\addInport pub, priv['process'], priv['port'], priv['metadata']
  for pub in to['outports']
    priv = to['outports'][pub]
    base\addOutport pub, priv['process'], priv['port'], priv['metadata']
  for group in to['groups']
    base\addGroup group['name'], group['nodes'], group['metadata']

expots['equivalent'] = (a, b, options = {}) =>
  -- TODO: add option to only compare known fields
  -- TODO: add option to ignore metadata
  A = json.encode a --JSON.stringify a -- find a way to stringify a table
  B = json.encode b --JSON.stringify b -- find a way to stringify a tab;e
  return A == B

expots['mergeResolveTheirs'] = mergeResolveTheirsNaive


return expots
