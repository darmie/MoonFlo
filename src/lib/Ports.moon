--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license


--Generic object clone. Based on NoFlo's Implementation

moon = require "moon"

module "Ports", package.seeall
export InPorts, OutPorts

{EventEmitter} = require 'events'

InPort = require 'InPort'
OutPort = require 'OutPort'

class Ports extends EventEmitter
  model: InPort
  new: (ports) =>
    @ports = {}
    return unless ports
    for name, options in ports
      @add name, options

  add: (name, options, process) =>
    if name == 'add' or name == 'remove'
      print "Error => Add and remove are restricted port names"

    unless name\match '^[a-z0-9_\.\/]+$'
      print "Error =>Port names can only contain lowercase alphanumeric characters and underscores. '#{name}' not allowed"

    --Remove previous implementation
    @remove name if @ports[name]

    if type(options) == 'table' and options.canAttach
      @ports[name] = options
    else
      @ports[name] = @model options, process

    @[name] = @ports[name]

    @emit 'add', name

    @ -- chainable

  remove: (name) =>
    print "Error => Port #{name} not defined" unless @ports[name]
    @ports[name] = nil
    @[name] = nil
    @emit 'remove', name

    @ -- chainable

InPorts = class InPorts extends Ports
  on: (name, event, callback) =>
    print "Error Port #{name} not available" unless @ports[name]
    @ports[name]\on event, callback
  once: (name, event, callback) =>
    print "Error Port #{name} not available" unless @ports[name]
    @ports[name]\once event, callback

OutPorts = class OutPorts extends Ports
  model: OutPort

  connect: (name, socketId) =>
    print "Error => Port #{name} not available" unless @ports[name]
    @ports[name]\connect socketId
  beginGroup: (name, group, socketId) ->
    print "Error =>Port #{name} not available" unless @ports[name]
    @ports[name]\beginGroup group, socketId
  send: (name, data, socketId) ->
    print "Error =>Port #{name} not available" unless @ports[name]
    @ports[name]\send data, socketId
  endGroup: (name, socketId) ->
    print "Error =>Port #{name} not available" unless @ports[name]
    @ports[name]\endGroup socketId
  disconnect: (name, socketId) ->
    print "Error =>Port #{name} not available" unless @ports[name]
    @ports[name]\disconnect socketId
