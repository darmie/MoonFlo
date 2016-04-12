module("indexOf", package.seeall)

indexOf = function ( t, object )
    if "table" == type( t ) then
        for i = 1, #t do
            if object == t[i] then
                return i
            end
        end
        return -1
    else
            error("table.indexOf expects table for first argument, " .. type(t) .. " given")
    end
end
