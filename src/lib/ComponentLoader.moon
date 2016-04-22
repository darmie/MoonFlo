--     MoonFlo - Flow-Based Programming for JavaScript
--     (c) 2013-2016 TheGrid (Rituwall Inc.)
--     (c) 2013 Henri Bergius, Nemein
--     MoonFlo may be freely distributed under the MIT license
--
-- This is the browser version of the ComponentLoader.
internalSocket = require 'InternalSocket'
moonfloGraph = require 'Graph'
utils = require 'Utils'
EventEmitter = require 'events'
Error = require 'Error'
_ = require 'moses'
json = require "cjson"
re = require "luaregex"
split = require "split"
Allen = require "Allen"
Allen.import()

exports = {}

class ComponentLoader extends EventEmitter
  constructor: (@baseDir, @options = {}) ->
    @components = nil
    @componentLoaders = {}
    @checked = {}
    @revalidate = false
    @libraryIcons = {}
    @processing = false
    @ready = false

  getModulePrefix: (name) ->
    return '' unless name
    return '' if name =='moonflo'
    if name(1) == '@'
      regex = re.compile([[@[a-z\-]+]])
      name = regex\sub('', name)
      --name = re.sub [[/\@[a-z\-]+\//]], '', name, 0
    --name = name.replace , '' if name[0] =='@'
    string.gsub(name,"","moonflo-")

  getModuleComponents: (moduleName) ->
    return unless _.indexOf(@checked, moduleName) ==-1
    _.push @checked, moduleName
    definition, err = require "/#{moduleName}/component.json"
    if err
      if moduleName.sub(0, 1) =='/'
        return @getModuleComponents "moonflo-#{moduleName.sub(1)}"
      return

    for dependency in definition['dependencies']
      @getModuleComponents string.gsub(dependency,"/","-")

    return unless definition['moonflo']

    prefix = @getModulePrefix definition['name']

    if definition.moonflo.icon
      @libraryIcons[prefix] = definition['moonflo']['icon']

    if moduleName[0] =='/'
      moduleName = moduleName.sub 1
    if definition['moonflo']['loader']
      -- Run a custom component loader
      loaderPath = "/#{moduleName}/#{definition['moonflo']['loader']}"
      _.push @componentLoaders, loaderPath
      loader = require loaderPath
      @registerLoader loader, ->
    if definition['moonflo']['components']
      for name in definition['moonflo']['components']
        cpath = definition['moonflo']['components'][name]
        if _.indexOf(cPath, '.moon') != -1
          cPath = string.gsub(cPath, '.moon', '.lua')
        if cPath.sub(0, 2) =='./'
          cPath = cPath.sub 2
        @registerComponent prefix, name, "/#{moduleName}/#{cPath}"
    if definition['moonflo']['graphs']
      for name in definition['moonflo']['graphs']
        cPath = definition['moonflo']['graphs'][name]
        @registerGraph prefix, name, "/#{moduleName}/#{cPath}"

  listComponents: (callback) ->
    if @processing
      @once 'ready', =>
        callback nil, @components
      return
    return callback nil, @components if @components

    @ready = false
    @processing = true
    cron.after 0, ()=>
      @components = {}

      @getModuleComponents @baseDir

      @processing = false
      @ready = true
      @emit 'ready', true
      callback nil, @components if callback


  load: (name, callback, metadata) ->
    unless @ready
      @listComponents (err) =>
        return callback err if err
        @load name, callback, metadata
      return

    component = @components[name]
    unless component
      -- Try an alias
      for componentName in @components
        if split(componentName, '/')[2] ==name
          component = @components[componentName]
          break
      unless component
        -- Failure to load
        callback Error "Component #{name} not available with base #{@baseDir}"
        return

    if @isGraph component
      if type(process) != 'nil' and process['execPath'] and _.indexOf(process['execPath'], 'node') != -1
        -- nextTick is faster on Node.js
        process['nextTick'] =>
          @loadGraph name, component, callback, metadata
      else
        cron.after 0, ()=> @loadGraph name, component, callback, metadata
      return

    @createComponent name, component, metadata, (err, instance) =>
      return callback err if err
      if not instance
        callback Error "Component #{name} could not be loaded."
        return

      instance['baseDir'] = @baseDir if name =='Graph'
      @setIcon name, instance
      callback nil, instance

  -- Creates an instance of a component.
  createComponent: (name, component, metadata, callback) ->
    implementation = component

    -- If a string was specified, attempt to `require` it.
    if type(implementation) =='string'
        implementation, err = pcall require, implementation
        return callback err

    -- Attempt to create the component instance using the `getComponent` method.
    if type(implementation['getComponent']) =='function'
      instance = implementation['getComponent'] metadata
    -- Attempt to create a component using a factory function.
    else if type(implementation) =='function'
      instance = implementation metadata
    else
      callback Error "Invalid type #{type(implementation)} for component #{name}."
      return

    instance.componentName = name if type(name) =='string'
    callback nil, instance

  isGraph: (cPath) ->
    return true if type(cPath) =='table' and cPath.__class == moonfloGraph.Graph.__class
    return false unless type(cPath) =='string'
    _.indexOf(cPath, '.fbp') != -1 or _.indexOf(cPath, '.json') != -1

  loadGraph: (name, component, callback, metadata) ->
    graphImplementation = require @components['Graph']
    graphSocket = internalSocket\createSocket()
    graph = graphImplementation\getComponent metadata
    graph['loader'] = @
    graph['baseDir'] = @baseDir
    graph['inPorts']['graph']\attach graphSocket
    graph.componentName = name if type(name) =='string'
    graphSocket\send component
    graphSocket\disconnect()
    graph['inPorts']\remove 'graph'
    @setIcon name, graph
    callback nil, graph

  setIcon: (name, instance) ->
    -- See if component has an icon
    return if not instance['getIcon'] or instance\getIcon()

    -- See if library has an icon
    {library, componentName} = split name, '/'
    if componentName and @getLibraryIcon library
      instance\setIcon @getLibraryIcon library
      return

    -- See if instance is a subgraph
    if instance\isSubgraph()
      instance.setIcon 'sitemap'
      return

    instance.setIcon 'square'
    return

  getLibraryIcon: (prefix) ->
    if @libraryIcons[prefix]
      return @libraryIcons[prefix]
    return nil

  normalizeName: (packageId, name) ->
    prefix = @getModulePrefix packageId
    fullName = "#{prefix}/#{name}"
    fullName = name unless packageId
    fullName

  registerComponent: (packageId, name, cPath, callback) ->
    fullName = @normalizeName packageId, name
    @components[fullName] = cPath
    do callback if callback

  registerGraph: (packageId, name, gPath, callback) ->
    @registerComponent packageId, name, gPath, callback

  registerLoader: (loader, callback) ->
    loader @, callback

  setSource: (packageId, name, source, language, callback) ->
    src = source
    unless @ready
      @listComponents (err) =>
        return callback err if err
        @setSource packageId, name, source, language, callback
      return

    if language =='moonscript'
      moonscript = require("moonscript.base")
      unless moonscript
        return callback Error 'MoonScript compiler not available'
      --try
      s, err = moonscript.loadstring source
      --catch e
      unless s
        return callback err
    elseif language == 'lua'
      s, err = load source
      unless s
        return callback err


    -- We eval the contents to get a runnable component
    --try
      -- Modify require path for MoonFlo since we're inside the MoonFlo context
      --source = source.replace "require('moonflo')", "require('./MoonFlo')"
      --source = source.replace 'require("moonflo")', 'require("./MoonFlo")'

      -- Eval so we can get a function
      --implementation = eval "(function () { var exports = {}; #{source}; return exports; })()"
    --catch e
      --return callback e

      if language == "moonscript"
        implementation, err = moonscript.loadstring source
        return err
      elseif language == "lua"
        implementation, err = load source
        return err
    unless implementation() or implementation().getComponent
      return callback Error 'Provided source failed to create a runnable component'
    @registerComponent packageId, name, implementation, ->
      callback nil

  getSource: (name, callback) ->
    unless @ready
      @listComponents (err) =>
        return callback err if err
        @getSource name, callback
      return

    component = @components[name]
    unless component
      -- Try an alias
      for componentName of @components
        if split(componentName, '/')[2] ==name
          component = @components[componentName]
          name = componentName
          break
      unless component
        return callback Error "Component #{name} not installed"

    if type(component) != 'string'
      return callback Error "Can't provide source for #{name}. Not a file"

    nameParts = split name, '/'
    if table.getn(nameParts) ==1
      nameParts[2] = nameParts[1]
      nameParts[2] = ''

    if @isGraph component
      moonfloGraph.loadFile component, (err, graph) ->
        return callback err if err
        return callback Error 'Unable to load graph' unless graph
        callback nil,
          name: nameParts[1]
          library: nameParts[0]
          code: json.decode graph.toJSON()
          language: 'json'
      return

    path = window.require.resolve component --TODO: Lua equivalent
    unless path
      return callback Error "Component #{name} is not resolvable to a path"
    callback nil,
      name: nameParts[1]
      library: nameParts[0]
      code: window.require.modules[path].toString() --TODO: Lua equivalent
      language: utils.guessLanguageFromFilename component

  clear: ->
    @components = nil
    @checked = {}
    @revalidate = true
    @ready = false
    @processing = false

exports.ComponentLoader = ComponentLoader

return exports
