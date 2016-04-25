--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license

-- MoonFlo is a Flow-Based Programming environment for MoonScript and Lua. This file provides the main entry point to the NoFlo network.
--
-- Find out more about using NoFlo from <http://moonflo.org/documentation/>

--Main APIs

--Graph interface
--module "MoonFlo", package.seeall
local exports = {}
-- Graph is used for instantiating FBP graph definitions.
graph = require('Graph')
exports['Graph'] = graph.Graph

-----Graph journal

--Journal is used for keeping track of graph changes
journal = require('Journal')
exports['Journal'] = journal.Journal

--Network interface

--Network is used for running NoFlo graphs.
exports['Network'] = require('Network').Network

-- Platform detection



-----Component Loader
--
--The ComponentLoader is responsible for finding and loading
--MoonFlo components.
--
-- this will utilize the default Lua require function

exports['ComponentLoader'] = require('ComponentLoader').ComponentLoader

--------Component baseclasses
--
--These baseclasses can be used for defining NoFlo components.

exports['Component'] = require('Component').Component
exports['AsyncComponent'] = require('AsyncComponent').AsyncComponent

--------Component helpers
--
--These helpers aid in providing specific behavior in components with minimal overhead.
helpers = require 'Helpers'

--------NoFlo ports
--
--These classes are used for instantiating ports on MoonFlo components.

ports = require 'Ports'
exports['InPorts'] = ports.InPorts
exports['OutPorts'] = ports.OutPorts
exports['InPort'] = require 'InPort'
exports['OutPort'] = require 'OutPort'


exports['Port'] = require('Port').Port
exports['ArrayPort'] = require('ArrayPort').ArrayPort

--------MoonFlo sockets
--
--The MoonFlo internalSocket is used for connecting ports of
--different components together in a network.
exports['internalSocket'] = require('InternalSocket')

--------Information Packets
--
--MoonFlo Information Packets are defined as "IP" objects.
exports['IP'] = require 'IP'

------Network instantiation
--
--This function handles instantiation of MoonFlo networks from a Graph object. It creates
--the network, and then starts execution by sending the Initial Information Packets.
--
--    moonflo.createNetwork someGraph, (err, network) ->
--      print 'Network is now running!'
--
--
--It is also possible to instantiate a Network but delay its execution by giving the
--third `delay` parameter. In this case you will have to handle connecting the graph and
--sending of IIPs manually.
--
--func = (err, network)->
--           if err
--              error err

--           network.connect (err) ->
--              network.start()
--              print 'Network is now running!'


--moonflo.createNetwork someGraph, func, true


exports['createNetwork'] = (graph, callback, options) ->
  unless type(options) == 'table'
    options =
      delay: options
  unless type(callback) == 'function'
    callback = (err) ->
      Error err if err

  network = Network graph, options

  networkReady = (network) ->
    --Send IIPs
    network.start (err) ->
      return callback err if err
      callback nil, network

  --Ensure components are loaded before continuing
  network.loader.listComponents (err) ->
    return callback err if err
    --Empty network, no need to connect it up
    return networkReady network if table.getn(graph.nodes) is 0

    --In case of delayed execution we don't wire it up
    if options.delay
      callback null, network
      return

    --Wire the network up and start execution
    network.connect (err) ->
      return callback err if err
      networkReady network

  network

--------Starting a network from a file
--
--It is also possible to start a NoFlo network by giving it a path to a `.json` or `.fbp` network
--definition file.
--
--    moonflo.loadFile 'somefile.json', (err, network) ->
--      if err
--        error err
--
--      print 'Network is now running!'
--
exports['loadFile']= (file, options, callback) ->
  unless callback
    callback = options
    baseDir = null

  if callback and type(options) != 'table'
    options =
      baseDir: options

  graph.loadFile file, (err, net) ->
    return callback err if err
    net.baseDir = options.baseDir if options.baseDir
    createNetwork net, callback, options

--------Saving a network definition
--
--MoonFlo graph files can be saved back into the filesystem with this method.
exports['saveFile'] = (graph, file, callback) ->
  graph.save file, -> callback file

return exports  
