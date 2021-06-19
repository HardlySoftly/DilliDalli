local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

function WaitingOnCommands(cmds)
    for _, cmd in cmds do
        if not IsCommandDone(cmd) then
            return true
        end
    end
    return false
end

function FindLocation(aiBrain, baseManager, intelManager, blueprint, location, radius, locationBias)
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
        local dx = intelManager.centre[1] - location[1]
        local dz = intelManager.centre[3] - location[3]
        local norm = math.sqrt(dx*dx+dz*dz)
        local x = math.floor(location[1]+(dx*buildRadius)/(norm*2)+Random(-1,1))+0.5
        local z = math.floor(location[3]+(dz*buildRadius)/(norm*2)+Random(-1,1))+0.5
        targetLocation = {x,GetSurfaceHeight(x,z),z}
    elseif locationBias == "defence" then
        -- Bias location defensively, taking into account similar units
    else
        local x = math.floor(location[1]+Random(-5,5))+0.5
        local z = math.floor(location[3]+Random(-5,5))+0.5
        targetLocation = {x,GetSurfaceHeight(x,z),z}
    end
    -- Step 2: Iterate through candidate locations in order
    local start = table.copy(targetLocation)
    local ring = 0
    local ringSize = 0
    local ringIndex = 0
    local iterations = 0
    local result
    local maxIterations = 1000000 -- 1000x1000 square
    while iterations < maxIterations do
        iterations = iterations + 1
        if aiBrain:CanBuildStructureAt(blueprint.BlueprintId,targetLocation) and intelManager:CanPathToSurface(location,targetLocation)
                                                                             and baseManager:LocationIsClear(targetLocation,blueprint) then
            -- TODO add adjacency check support
            return targetLocation
        end
        -- Update targetLocation
        if ringIndex == ringSize then
            ring = ring+1
            ringIndex = 0
            ringSize = 8*ring
            local x = start[1]+ring
            local z = start[3]+ring
            targetLocation = {x,GetSurfaceHeight(x,z),z}
        else
            local x = targetLocation[1]
            local z = targetLocation[3]
            if ringIndex < 2*ring then
                -- Move up
                z = z-1
            elseif ringIndex < ring*4 then
                -- Move left
                x = x-1
            elseif ringIndex < ring*6 then
                -- Move down
                z = z+1
            else
                -- Move right
                x = x+1
            end
            ringIndex = ringIndex + 1
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
    local pos = FindLocation(aiBrain,brain.base,brain.intel,bp,location,radius,"centre")
    if pos then
        -- Clear any existing commands
        IssueClearCommands({engie})
        -- Now issue build command
        -- I need a unique token.  This is unique with high probability (0,2^30 - 1).
        local constructionID = Random(0,1073741823)
        brain.base:BaseIssueBuildMobile({engie},pos,bp,constructionID)
        while engie and (not engie.Dead) and table.getn(engie:GetCommandQueue()) > 0 do
            WaitTicks(2)
        end
        brain.base:BaseCompleteBuildMobile(constructionID)
        return true
    else
        WARN("Failed to find position to build: "..tostring(structure))
        return false
    end
end

function EngineerBuildMarkedStructure(brain,engie,structure,markerType)
    local aiBrain = engie:GetAIBrain()
    local bp = aiBrain:GetUnitBlueprint(structure)
    local pos = brain.intel:FindNearestEmptyMarker(engie:GetPosition(),markerType).position
    if pos then
        IssueClearCommands({engie})
        -- I need a unique token.  This is unique with high probability (0,2^30 - 1).
        local constructionID = Random(0,1073741823)
        brain.base:BaseIssueBuildMobile({engie},pos,bp,constructionID)
        while engie and (not engie.Dead) and table.getn(engie:GetCommandQueue()) > 0 do
            WaitTicks(2)
        end
        brain.base:BaseCompleteBuildMobile(constructionID)
        if (not engie) or engie.Dead then
            return true
        end
        local target = brain.intel:GetEnemyStructure(pos)
        if target then
            IssueReclaim({engie},target)
            brain.base:BaseIssueBuildMobile({engie},pos,bp,constructionID)
            while engie and (not engie.Dead) and table.getn(engie:GetCommandQueue()) > 0 do
                WaitTicks(2)
            end
            brain.base:BaseCompleteBuildMobile(constructionID)
        end
        return true
    else
        WARN("Failed to find position for markerType: "..tostring(markerType))
        return false
    end
end

function EngineerAssist(engie,target)
    IssueClearCommands({engie})
    IssueGuard({engie},target)
    while target and (not target.Dead) and engie and (not engie.Dead) and (not engie.CustomData.assistComplete) do
        WaitTicks(2)
    end
    if engie and (not engie.Dead) then
        -- Reset this engie
        IssueClearCommands({engie})
        engie.CustomData.assistComplete = nil
    end
end

function FactoryBuildUnit(fac,unit)
    IssueClearCommands({fac})
    IssueBuildFactory({fac},unit,1)
    while fac and not fac.Dead and not fac:IsIdleState() do
        -- Like, I know this is hammering something but you can't afford to wait on facs.
        -- In the future I want to queue up stuff properly, but for now just deal with it.
        WaitTicks(1)
    end
end