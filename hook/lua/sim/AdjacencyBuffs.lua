function GetAdjacencyBuffs()
    local res = {}
    for k, v in adj do
        res[k..'AdjacencyBuffs'] = table.deepcopy(v)
    end
    return res
end
