--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license
_ = require 'moses'

module("IP", package.seeall)
export IP

class IP
  --Valid IP types
  @types: {
    'data'
    'openBracket'
    'closeBracket'
  }
  print @types
  --Detects if an arbitrary value is an IP
  @isIP: (obj) =>
    obj and type(obj) == 'table' and obj.type and _.indexOf(@types, obj.type) > -1

  --Creates as new IP object
  --Valid types: 'data', 'openBracket', 'closeBracket'
  new: (@type = 'data', @data = nil, options = {}) =>
    @groups = {} --sync groups
    @scope = nil --sync scope id
    @owner = nil --packet owner process
    @clonable = false --cloning safety flag
    @index = nil --addressable port index
    for key, val in pairs options
      this[key] = val

  --Creates a new IP copying its contents by value not reference
  clone: =>
    ip = IP @type
    for key, val in pairs @
      continue if _.indexOf({'owner'}, key) != -1
      continue if val == nil
      if type(val) == 'table'
        ip[key] = val --JSON.parse JSON.stringify val
      else
        ip[key] = val
    ip

  --Moves an IP to a different owner
  move: (@owner) ->
    --no-op

  --Frees IP contents
  drop: =>
    print @
    for key, val in pairs @
       this[key] = nil
