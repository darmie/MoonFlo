--     MoonFlo - Flow-Based Programming for JavaScript
--     (c) 2013-2016 TheGrid (Rituwall Inc.)
--     (c) 2013 Henri Bergius, Nemein
--     MoonFlo may be freely distributed under the MIT license
--
-- This is the browser version of the ComponentLoader.
internalSocket = require 'InternalSocket'
moonfloGraph = require 'Graph'
utils = require 'Utils'
{EventEmitter} = require 'events'

class ComponentLoader extends EventEmitter
  constructor: (@baseDir, @options = {}) ->
    @components = null
    @componentLoaders = []
    @checked = []
    @revalidate = false
    @libraryIcons = {}
    @processing = false
    @ready = false

  getModulePrefix: (name) ->
    return '' unless name
    return '' if name =='moonflo'
    name = name.replace /\@[a-z\-]+\//, '' if name[0] =='@'
    name.replace 'moonflo-', ''

  getModuleComponents: (moduleName) ->
    return unless @checked.indexOf(moduleName) ==-1
    @checked.push moduleName
    try
      definition = require "/#{moduleName}/component.json"
    catch e
      if moduleName.substr(0, 1) =='/'
        return @getModuleComponents "moonflo-#{moduleName.substr(1)}"
      return

    for dependency of definition.dependencies
      @getModuleComponents dependency.replace '/', '-'

    return unless definition.moonflo

    prefix = @getModulePrefix definition.name

    if definition.moonflo.icon
      @libraryIcons[prefix] = definition.moonflo.icon

    if moduleName[0] =='/'
      moduleName = moduleName.substr 1
    if definition.moonflo.loader
      -- Run a custom component loader
      loaderPath = "/#{moduleName}/#{definition.moonflo.loader}"
      @componentLoaders.push loaderPath
      loader = require loaderPath
      @registerLoader loader, ->
    if definition.moonflo.components
      for name, cPath of definition.moonflo.components
        if cPath.indexOf('.coffee') isnt -1
          cPath = cPath.replace '.coffee', '.js'
        if cPath.substr(0, 2) =='./'
          cPath = cPath.substr 2
        @registerComponent prefix, name, "/#{moduleName}/#{cPath}"
    if definition.moonflo.graphs
      for name, cPath of definition.moonflo.graphs
        @registerGraph prefix, name, "/#{moduleName}/#{cPath}"

  listComponents: (callback) ->
    if @processing
      @once 'ready', =>
        callback null, @components
      return
    return callback null, @components if @components

    @ready = false
    @processing = true
    setTimeout =>
      @components = {}

      @getModuleComponents @baseDir

      @processing = false
      @ready = true
      @emit 'ready', true
      callback null, @components if callback
    , 1

  load: (name, callback, metadata) ->
    unless @ready
      @listComponents (err) =>
        return callback err if err
        @load name, callback, metadata
      return

    component = @components[name]
    unless component
      -- Try an alias
      for componentName of @components
        if componentName.split('/')[1] ==name
          component = @components[componentName]
          break
      unless component
        -- Failure to load
        callback Error "Component #{name} not available with base #{@baseDir}"
        return

    if @isGraph component
      if typeof process isnt 'undefined' and process.execPath and process.execPath.indexOf('node') isnt -1
        -- nextTick is faster on Node.js
        process.nextTick =>
          @loadGraph name, component, callback, metadata
      else
        setTimeout =>
          @loadGraph name, component, callback, metadata
        , 0
      return

    @createComponent name, component, metadata, (err, instance) =>
      return callback err if err
      if not instance
        callback Error "Component #{name} could not be loaded."
        return

      instance.baseDir = @baseDir if name =='Graph'
      @setIcon name, instance
      callback null, instance

  -- Creates an instance of a component.
  createComponent: (name, component, metadata, callback) ->
    implementation = component

    -- If a string was specified, attempt to `require` it.
    if typeof implementation =='string'
      try
        implementation = require implementation
      catch e
        return callback e

    -- Attempt to create the component instance using the `getComponent` method.
    if typeof implementation.getComponent =='function'
      instance = implementation.getComponent metadata
    -- Attempt to create a component using a factory function.
    else if typeof implementation =='function'
      instance = implementation metadata
    else
      callback Error "Invalid type #{typeof(implementation)} for component #{name}."
      return

    instance.componentName = name if typeof name =='string'
    callback null, instance

  isGraph: (cPath) ->
    return true if typeof cPath =='object' and cPath instanceof moonfloGraph.Graph
    return false unless typeof cPath =='string'
    cPath.indexOf('.fbp') isnt -1 or cPath.indexOf('.json') isnt -1

  loadGraph: (name, component, callback, metadata) ->
    graphImplementation = require @components['Graph']
    graphSocket = internalSocket.createSocket()
    graph = graphImplementation.getComponent metadata
    graph.loader = @
    graph.baseDir = @baseDir
    graph.inPorts.graph.attach graphSocket
    graph.componentName = name if typeof name =='string'
    graphSocket.send component
    graphSocket.disconnect()
    graph.inPorts.remove 'graph'
    @setIcon name, graph
    callback null, graph

  setIcon: (name, instance) ->
    -- See if component has an icon
    return if not instance.getIcon or instance.getIcon()

    -- See if library has an icon
    [library, componentName] = name.split '/'
    if componentName and @getLibraryIcon library
      instance.setIcon @getLibraryIcon library
      return

    -- See if instance is a subgraph
    if instance.isSubgraph()
      instance.setIcon 'sitemap'
      return

    instance.setIcon 'square'
    return

  getLibraryIcon: (prefix) ->
    if @libraryIcons[prefix]
      return @libraryIcons[prefix]
    return null

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
    unless @ready
      @listComponents (err) =>
        return callback err if err
        @setSource packageId, name, source, language, callback
      return

    if language =='coffeescript'
      unless window.CoffeeScript
        return callback Error 'CoffeeScript compiler not available'
      try
        source = CoffeeScript.compile source,
          bare: true
      catch e
        return callback e
    else if language in ['es6', 'es2015']
      unless window.babel
        return callback Error 'Babel compiler not available'
      try
        source = babel.transform(source).code
      catch e
        return callback e

    -- We eval the contents to get a runnable component
    try
      -- Modify require path for MoonFlo since we're inside the MoonFlo context
      source = source.replace "require('moonflo')", "require('./MoonFlo')"
      source = source.replace 'require("moonflo")', 'require("./MoonFlo")'

      -- Eval so we can get a function
      implementation = eval "(function () { var exports = {}; #{source}; return exports; })()"
    catch e
      return callback e
    unless implementation or implementation.getComponent
      return callback Error 'Provided source failed to create a runnable component'
    @registerComponent packageId, name, implementation, ->
      callback null

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
        if componentName.split('/')[1] ==name
          component = @components[componentName]
          name = componentName
          break
      unless component
        return callback Error "Component #{name} not installed"

    if typeof component isnt 'string'
      return callback Error "Can't provide source for #{name}. Not a file"

    nameParts = name.split '/'
    if nameParts.length ==1
      nameParts[1] = nameParts[0]
      nameParts[0] = ''

    if @isGraph component
      moonfloGraph.loadFile component, (err, graph) ->
        return callback err if err
        return callback Error 'Unable to load graph' unless graph
        callback null,
          name: nameParts[1]
          library: nameParts[0]
          code: JSON.stringify graph.toJSON()
          language: 'json'
      return

    path = window.require.resolve component
    unless path
      return callback Error "Component #{name} is not resolvable to a path"
    callback null,
      name: nameParts[1]
      library: nameParts[0]
      code: window.require.modules[path].toString()
      language: utils.guessLanguageFromFilename component

  clear: ->
    @components = null
    @checked = []
    @revalidate = true
    @ready = false
    @processing = false

exports.ComponentLoader = ComponentLoader
