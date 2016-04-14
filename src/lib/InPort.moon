--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license


--Input Port (inport) implementation for MoonFlo components
module "InPort", package.seeall
export InPort

BasePort = require 'BasePort'
IP = require 'IP'
_ = require 'moses'
filter = require 'filter'

class InPort extends BasePort
  new: (options, process) =>
    @process = nil

    if not process and typeof options == 'function'
      process = options
      options = {}

    if options == nil then options ={}

    if options['buffered'] == nil then   options['buffered'] = false
    if options['control'] == nil then options['control'] = false
    if options['triggering'] == nil then options['triggering'] =  true

    if not process and options and options['process']
      process = options['process']
      --delete options['process']
      table.remove options, options['process']

    if process
      unless type(process) == 'function'
        error 'process must be a function'
      @process = process

    if options['handle']
      unless type(options['handle']) == 'function'
        error 'handle must be a function'
      @handle = options['handle']
      --delete options['handle']
      table.remove options, options['handle']

    super options

    @prepareBuffer()

  attachSocket: (socket, localId = nil) =>

    --Assign a delegate for retrieving data should this inPort
    --have a default value.
    if @hasDefault()
      if @handle
        socket.setDataDelegate => IP 'data', @options.default
      else
        socket.setDataDelegate => @options.default

    socket\on 'connect', =>
      @handleSocketEvent 'connect', socket, localId
    socket\on 'begingroup', (group) =>
      @handleSocketEvent 'begingroup', group, localId
    socket\on 'data', (data) =>
      @validateData data
      @handleSocketEvent 'data', data, localId
    socket\on 'endgroup', (group) =>
      @handleSocketEvent 'endgroup', group, localId
    socket\on 'disconnect', =>
      @handleSocketEvent 'disconnect', socket, localId
    socket\on 'ip', (ip) =>
      @handleIP ip, localId

  handleIP: (ip, id) =>
    return if @process
    return if @options['control'] and ip['type'] != 'data'
    ip['owner'] = @nodeInstance
    ip['index'] = id

    if ip['scope']
      @scopedBuffer[ip['scope']] = nil  unless _.contains(@scopedBuffer, ip['scope'])
      buf = @scopedBuffer[ip['scope']]
    else
      buf = @buffer
    _.push buf, ip
    _.pop(buf) if @options['control'] and table.getn(buf) > 1  --TODO: confirm if _.shift() exists in moses

    if @handle
      @handle ip, @nodeInstance

    @emit 'ip', ip, id

  handleSocketEvent: (event, payload, id) =>
    --Handle buffering the old way
    if @isBuffered()
      _.push @buffer
        event: event
        payload: payload
        id: id

      --Notify receiver
      if @isAddressable()
        @process event, id, @nodeInstance if @process
        @emit event, id
      else
        @process event, @nodeInstance if @process
        @emit event
      return

    if @process
      if @isAddressable()
        @process event, payload, id, @nodeInstance
      else
        @process event, payload, @nodeInstance

    --Emit port event
    return @emit event, payload, id if @isAddressable()
    @emit event, payload

  hasDefault: =>
    return @options['default'] != nil

  prepareBuffer: =>
    @buffer = {}
    @scopedBuffer = {}

  validateData: (data) =>
    return unless @options['values']
    if _.indexOf(@options['values'], data) == -1
      error "Invalid data='#{data}' received, not in [#{@options['values']}]"

  --Returns the next packet in the (legacy) buffer
  receive: =>
    unless @isBuffered()
      error 'Receive is only possible on buffered ports'
    _.pop(@buffer)

  --Returns the number of data packets in a (legacy) buffered inport
  contains: =>
    unless @isBuffered()
      error 'Contains query is only possible on buffered ports'
    table.getn filter(@buffer, (packet) -> return true if packet['event'] == 'data')

  --Fetches a packet from the port
  get: (scope) =>
    if scope
      return nil unless _.contains @scopedBuffer, scope
      buf = @scopedBuffer[scope]
    else
      buf = @buffer
    return if @options['control'] then buf[table.getn(buf) - 1] else _.shift(buf)

  --Returns the number of data packets in an inport
  length: (scope) =>
    if scope
      return 0 unless scope of @scopedBuffer
      return table.getn @scopedBuffer[scope]
    return table.getn @buffer

  --Tells if buffer has packets or not
  ready: (scope) =>
    return @length(scope) > 0
