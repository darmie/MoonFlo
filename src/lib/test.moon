--re = dofile "luaregex.lua"
--require "moonscript"
--Error = loadfile "Error"
--name = '@moonflo'
--regex = re.compile([[@[a-z\-]+]])
--subb = regex\sub('', name)
package.path = ';?.lua;C:/Lua/systree/share/lua/5.1/?.lua'
package.moonpath = ';?.moon'
require "moonscript"
error = require "Error"
split = require "split"
--_ = require "Allen"
--_.import()
moses = require "moses"
--_.import()
--print string.capitalize('hello')
name = "H/e/l/lo"
--print name.splice 2,2,'r'

--print name\sub(1)
--print name[1]

--print _.lines(name)[1]
--for i= 1, 5 --table.getn(split(name , '/'))
  --print i
  --print split(name, '/')[i]


--print package.searchers[1] 'moses'

for _, searcher in ipairs(package.searchers or package.loaders) do
      loader = searcher('moses')
      if type(loader) == 'function' then
        package.preload['moses'] = loader
        print package.preload['moses']
