module("splice", package.seeall)

splice = function(t,i,len, replaceWith)
	if (len > 0) then
		for r=0, len do
			if(r < len) then
				table.remove(t,i + r)
			end
		end
	end
	if(replaceWith) then
		table.insert(t,i,replaceWith)
	end
	local count = 1
	local tempT = {}
	for i=1, #t do
		if t[i] then
			tempT[count] = t[i]
			count = count + 1
		end
	end
	t = tempT
end
