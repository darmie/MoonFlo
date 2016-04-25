--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license


--Generic object clone. Based on NoFlo's Implementation

moon = require "moon"

--module "Utils", package.seeall
exports = {}

clone = (obj)->
  unless type(obj) != 'table'
    return obj

  if obj.__parent == moon.Date
    return os.date(os.time)


  newInstance = moon.bind_methods obj

  for key, value in pairs obj
    newInstance[key] = clone obj[key]

  return newInstance


--Guess language from filename
guessLanguageFromFilename = (filename) ->
    regex = re.compile([[]])
    if filename\match("^.+(%..+)$") == '.moon'
      return 'Moonscript'
    return 'Lua'
_.push exports, :clone, :guessLanguageFromFilename    
return exports
