function CheckForEnemyStructure(aiBrain,pos,radius)
    local units = aiBrain:GetUnitsAroundPoint( categories.STRUCTURE, pos, radius, 'Enemy' )
    if units and units[1] then
        return units[1]
    else
        return nil
    end
end