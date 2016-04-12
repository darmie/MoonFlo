--MoonFlo - Flow-Based Programming for MoonScript
--@Author Damilare Akinlaja, 2016
--MoonFlo may be freely distributed under the MIT license


--Generic object clone. Based on NoFlo's Implementation

moon = require "moon"

module "Utils", package.seeall
export clone, guessLanguageFromFilename

clone = (obj)->
  unless moon.type(obj) != 'table'
    return obj

  if obj.__parent == moon.Date
    return moon.Date(obj/getTime)


  newInstance = moon.bind_methods obj

  for key, value in pairs obj
    newInstance[key] = clone obj[key]

  return newInstance


--Guess language from filename
guessLanguageFromFilename = (filename) ->
    if filename\match("^.+(%..+)$") == '.moon'
      return 'Moonscript'
    return 'Lua'
