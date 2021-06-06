local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

function WaitingOnCommands(cmds)
    for _, cmd in cmds do
        if not IsCommandDone(cmd) then
            return true
        end
    end
    return false
end

function FindMarkerLocation(aiBrain,intelManager,blueprint,location,markerType)
    local markers = ScenarioUtils.GetMarkers()
    local best = 1000000
    local bestMarker = nil
    for _, v in markers do
        if v.type == markerType then
            local dist = VDist3(location,v.position)
            if dist < best and aiBrain:CanBuildStructureAt(blueprint.BlueprintId,v.position) then
                best = dist
                bestMarker = v
            end
        end
    end
    return bestMarker.position
end

function FindLocation(aiBrain, intelManager, blueprint, location, radius, massAdjacent, energyAdjacent, factoryAdjacent, locationBias)
    -- Fuck having this as a dependency: aiBrain:FindPlaceToBuild
    -- It is so miserably complex to call that I'm going to roll my own version right here. Fight me.

    -- Step 1: Identify starting location
    local targetLocation
    -- TODO: detect this dynamically
    local buildRadius = 10
    if locationBias == "enemy" then
        -- Bias location towards nearby enemy structures
    elseif locationBias == "centre" then
        -- Bias location towards the centre of the map
    elseif locationBias == "defence" then
        -- Bias location defensively, taking into account similar units
    else
        local x = location[1]+Random(-5,5)
        local z = location[3]+Random(-5,5)
        targetLocation = {x,GetSurfaceHeight(x,z),z}
    end
    -- Step 2: Iterate through candidate locations in order
    local ring = 0
    local ringSize = 0
    local ringIndex = 0
    local iterations = 0
    local result
    local maxIterations = 10000 -- 100x100 square
    while iterations < maxIterations do
        iterations = iterations + 1
        DrawCircle(targetLocation,1,'aa000000')
        if aiBrain:CanBuildStructureAt(blueprint.BlueprintId,targetLocation) then
            -- TODO add adjacency check support
            return targetLocation
        end
        -- Update targetLocation
        if ringIndex == ringSize then
            ring = ring+1
            ringIndex = 0
            ringSize = 8*ring
            local x = targetLocation[1]+1
            local z = targetLocation[3]+1
            targetLocation = {x,GetSurfaceHeight(x,z),z}
        else
            local x = targetLocation[1]
            local z = targetLocation[3]
            ringIndex = ringIndex + 1
            if ringIndex > 7*ring - 1 or ring <= ring-1 then
                -- Move to the right
                x = x+1
            elseif ringIndex > 5*ring-1 then
                -- Move up
                z = z+1
            elseif ringIndex > 3*ring-1 then
                -- Move to the left
                x = x-1
            else --if ringIndex > ring-1 then
                -- Move down
                z = z-1
            end
            targetLocation = {x,GetSurfaceHeight(x,z),z}
        end
    end
    return result
end

function EngineerBuildStructure(brain,engie,structure,location,radius)
    local aiBrain = engie:GetAIBrain()
    local bp = aiBrain:GetUnitBlueprint(structure)
    if not location then
        location = engie:GetPosition()
        radius = 40
    end
    local pos = FindLocation(aiBrain,brain.intel,bp,location,radius)
    if pos then
        -- Clear any existing commands
        IssueClearCommands({engie})
        -- Now issue build command
        local cmd = IssueBuildMobile({engie},pos,structure,{})
        while table.getn(engie:GetCommandQueue()) > 0 do
            WaitTicks(2)
        end
    else
        WARN("Failed to find position to build: "..tostring(structure))
    end
end

function EngineerBuildMarkedStructure(brain,engie,structure,markerType)
    local aiBrain = engie:GetAIBrain()
    local bp = aiBrain:GetUnitBlueprint(structure)
    local pos = FindMarkerLocation(aiBrain,brain.intel,bp,engie:GetPosition(),markerType)
    if pos then
        IssueClearCommands({engie})
        local cmd = IssueBuildMobile({engie},pos,structure,{})
        while table.getn(engie:GetCommandQueue()) > 0 do
            WaitTicks(2)
        end
    else
        WARN("Failed to find position for markerType: "..tostring(markerType))
    end
end

function EngineerAssist(baseController,engie,target)
end

function FactoryBuildUnit(fac,unit)
    IssueClearCommands({fac})
    IssueBuildFactory({fac},unit,1)
    while not fac:IsIdleState() do
        -- Like, I know this is hammering something but you can't afford to wait on facs.
        -- In the future I want to queue up stuff properly, but for now just deal with it.
        WaitTicks(1)
    end
end