function SplitString(s, d)
    local res = {}
    local start = 1
    local segEnd, segStart = string.find(s,d,start)
    while segEnd do
        table.insert(res,string.sub(s,start,segEnd-1))
        start = segStart + 1
        segEnd, segStart = string.find(s,d,start)
    end
    table.insert(res,string.sub(s,start))
    return res
end
