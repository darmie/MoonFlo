--re = dofile "luaregex.lua"
--require "moonscript"
--Error = loadfile "Error"
--name = '@moonflo'
--regex = re.compile([[@[a-z\-]+]])
--subb = regex\sub('', name)
package.path = package.path  .. ';?.lua;C:/Lua/systree/share/lua/5.1/?.lua'
--package.moonpath = package.moonpath .. ';?.moon'
--require "moonscript"
--error = require "Error"
--split = require "split"
_ = require "Allen"
_.import()
--moses = require "moses"
--_.import()
--print string.capitalize('hello')
name = "HELLO"

print string.lower(name)

print string.sub(name, 0, 2)

-- load the http module
--io = require "io"
--http = require "socket.http"
--ltn12 = require "ltn12"

-- connect to server "www.cs.princeton.edu" and retrieves this manual
-- file from "~diego/professional/luasocket/http.html" and print it to stdout
--http\request{url: [[http://www.cs.princeton.edu/~diego/professional/luasocket/http.html]] , sink: ltn12.sink\file(io.stdout)}

--print name.splice 2,2,'r'

--print name\sub(1)
--print name[1]

--print _.lines(name)[1]
--for i= 1, 5 --table.getn(split(name , '/'))
  --print i
  --print split(name, '/')[i]


--print package.searchers[1] 'moses'

--for _, searcher in ipairs(package.searchers or package.loaders) do
    --  loader = searcher('moses')
      --if type(loader) == 'function' then
        --package.preload['moses'] = loader
        --print package.preload['moses']
