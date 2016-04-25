

filter = function(t, filterIter)
  local out = {}

  for k, v in pairs(t) do
    if filterIter(v) then out[k] = v end
  end

  return out
end

return filter
