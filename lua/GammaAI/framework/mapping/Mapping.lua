local CreatePriorityQueue = import('/mods/DilliDalli/lua/GammaAI/framework/utils/PriorityQueue.lua').CreatePriorityQueue

--[[
    A table containing all the markers that are actually created.
    This is different to the MASTERCHAIN variable for adaptive maps, which only selectively create certain markers.
]]
local MYOWNMARKERS = {}
function CreateMarker(t,x,y,z,size)
    if map:IsInitialised() then
        local item = {
            type=t,
            position={x,y,z},
            components={
                map:GetComponent({x,y,z}, LAYER_LAND),
                map:GetComponent({x,y,z}, LAYER_NAVY),
                map:GetComponent({x,y,z}, LAYER_HOVER),
                map:GetComponent({x,y,z}, LAYER_AMPH)
            }
        }
        table.insert(MYOWNMARKERS,item)
        map:AddMarker(item)
    else
        table.insert(MYOWNMARKERS,{type=t,position={x,y,z}})
    end
end
function GetMarkers()
    return MYOWNMARKERS
end

--[[
    Similar to the marker table above, the map scenario info doesn't always reflect the actual playing area.
    This code tracks the actual map size as requested by the map script.
    Note that changes to the map size are only supported before the mapping code is run - dynamic changes to map size are not supported (maybe in the future...).
    This means no support for certain map scenarios (e.g. campaign style missions), and the claustrophobia mod.
]]
local DEFAULT_BORDER = 4
local PLAYABLE_AREA = nil
function SetPlayableArea(x0,z0,x1,z1)
    -- Fields of Isis is a bad map, I hate to be the one who has to say it.
    PLAYABLE_AREA = { x0, z0, x1, z1 }
end
function GetPlayableArea()
    return PLAYABLE_AREA
end

--[[
    Quick note on the remainder of the file:
    This code is largely written with performance in mind over readability.
    The justification in this case is that it represents a significant amount of work, and necessarily runs before the game starts.
    Every second here is a second the players are waiting to play.
    Previous iterations of this functionality ran in ~1 min timescales on 20x20 maps, necessitating a performance oriented re-write.
    Sorry for the inlining of functions, the repetitive code blocks, and the constant localling of variables :)
  ]]

--[[
    TARGET_MARKERS and MIN_GAP between them control the overall precision of the map - namely how far apart should map nodes be.
    For more details on this see GameMap:CreateMapMarkers()
]]
local TARGET_MARKERS = 120000
local MIN_GAP = 5

--[[
    This variable controls the tolerance when determining if terrain is pathable or not.  Terrain above MAX_GRADIENT steepness is considered impassable.
    Note that in this implementation of the mapping code, this isn't an exact science, so some tuning of this parameter was necessary to achieve a good tradeoff.
]]
local MAX_GRADIENT = 0.5

--[[
    The underwater clearance that ships and submersibles require to move (it is the same for both).
    See footprints.lua in mohodata.scd for the definition of this - I decided it was fine to hardcode in the end (would be _very_ niche to mod this value).
]]
local SHIP_CLEARANCE = 1.5

-- I use this constant a lot for diagonal distance calculations, so wanted to cache it.
local SQRT_2 = math.sqrt(2)

--[[
    Constants used for layer indices in the GameMap class.
    Wherever a 'layer' variable is used in the GameMap class, it will take one of these values (with the associated implied meaning).
    LAYER_NONE and LAYER_AIR are treated as special values in the GameMap class, and cannot be used as the layer index directly.
    i.e. MAP.markers[i][j][layer] isn't a valid thing to do for LAYER_NONE and LAYER_AIR.

    Changes here are not recommended for compatibility reasons, it would break:
        - external code that hardcodes layer values,
        - the GameMap:GetMostRestrictiveMovementLayer function.
    At some point in the future I may allow for exporting of these values in a sensible way (some kind of table?) so that they don't end up being hardcoded everywhere.
]]
local LAYER_NONE = -1
local LAYER_AIR = 0
local LAYER_LAND = 1
local LAYER_NAVY = 2
local LAYER_HOVER = 3
local LAYER_AMPH = 4

-- The max layer index - used for 'for' loops that iterate over each layer.
local NUM_LAYERS = 4

--[[
    A table containing all the functions for checking connectivity between two map nodes.
        - Note: it's a table so that I can collapse it more easily in my editor, and it just feels a bit cleaner than them all being their own locals.
    The X direction and Z direction checks are feature almost identical code and could be easily merged, but I wanted to avoid the performance impact of checking direction every call.
    These get called a *lot* - once for every node on the map, meaning up to around TARGET_MARKERS*8 calls between them.  Performance is king here.

    What do I mean by checking connectivity?
    These functions answer the question 'For the given layer, can you move between (x,z) and (x+gap,z) (or (x,z+gap) for the Z direction version) in a straight line?'.

    How do they work (for land/hover/amphib layers)?
    Firstly, the function will split the straight line between the start and end point into unit intervals (i.e. segments of length 1).
    The function will then check the Y values at the start and end of each segment, and compare the gradient to the MAX_GRADIENT value.
    If any of the segments exceed this value, it will return false.
    As it checks each segment in a straight line, it will also check unit length segments perpendicular to the line, and compare the gradient of these to MAX_GRADIENT too.
    This second check catches the case where the line is going along a cliff at a shallow angle, thereby appearing to be passable when it is actually very steep.
    If all these checks pass, then the function return true.

    There's also a couple of small differences in the way each layer is handled:
        - If any segment is below water level, then the land check fails.
        - The hover checks use GetSurfaceHeight (which returns water height where relevant).
        - The amphib checks use GetTerrainHeight.

    How does the naval one work?
    Since water is flat, the only check that needs doing is whether or not the water depth exceeds SHIP_CLEARANCE at each segment.
]]
local ConnectivityCheckingFunctions = {
    -- Land
    LandXDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        if GetTerrainHeight(x,z) < GetSurfaceHeight(x,z) then
            return false
        end
        for d = 1, gap do
            local g = (GetTerrainHeight(x+d-1,z) - GetTerrainHeight(x+d,z))
            if -gMax > g or g > gMax then
                return false
            end
            if GetTerrainHeight(x+d-1,z) < GetSurfaceHeight(x+d-1,z) then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetTerrainHeight(x+d,z) - GetTerrainHeight(x+d,z+1))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetTerrainHeight(x+d,z) - GetTerrainHeight(x+d,z-1))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
    LandZDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        if GetTerrainHeight(x,z) < GetSurfaceHeight(x,z) then
            return false
        end
        for d = 1, gap do
            local g = (GetTerrainHeight(x,z+d-1) - GetTerrainHeight(x,z+d))
            if -gMax > g or g > gMax then
                return false
            end
            if GetTerrainHeight(x,z+d-1) < GetSurfaceHeight(x,z+d-1) then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetTerrainHeight(x,z+d) - GetTerrainHeight(x+1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetTerrainHeight(x,z+d) - GetTerrainHeight(x-1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
    -- Naval / water surface
    NavalXDirection = function(x,z,gap)
        if GetTerrainHeight(x,z) >= GetSurfaceHeight(x,z)-SHIP_CLEARANCE then
            return false
        end
        for d = 1, gap do
            -- No need for gradient checks
            if GetTerrainHeight(x+d,z) >= GetSurfaceHeight(x+d,z)-SHIP_CLEARANCE then
                return false
            end
        end
        return true
    end,
    NavalZDirection = function(x,z,gap)
        if GetTerrainHeight(x,z) >= GetSurfaceHeight(x,z)-SHIP_CLEARANCE then
            return false
        end
        for d = 1, gap do
            -- No need for gradient checks
            if GetTerrainHeight(x,z+d-1) >= GetSurfaceHeight(x,z+d-1)-SHIP_CLEARANCE then
                return false
            end
        end
        return true
    end,
    -- Hover
    HoverXDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        for d = 1, gap do
            local g = (GetSurfaceHeight(x+d-1,z) - GetSurfaceHeight(x+d,z))
            if -gMax > g or g > gMax then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetSurfaceHeight(x+d,z) - GetSurfaceHeight(x+d,z+1))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetSurfaceHeight(x+d,z) - GetSurfaceHeight(x+d,z-1))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
    HoverZDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        for d = 1, gap do
            local g = (GetSurfaceHeight(x,z+d-1) - GetSurfaceHeight(x,z+d))
            if -gMax > g or g > gMax then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetSurfaceHeight(x,z+d) - GetSurfaceHeight(x+1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetSurfaceHeight(x,z+d) - GetSurfaceHeight(x-1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
    -- Amphibious
    AmphibiousXDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        for d = 1, gap do
            local g = (GetTerrainHeight(x+d-1,z) - GetTerrainHeight(x+d,z))
            if -gMax > g or g > gMax then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetTerrainHeight(x+d,z) - GetTerrainHeight(x+d,z+1))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetTerrainHeight(x+d,z) - GetTerrainHeight(x+d,z-1))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
    AmphibiousZDirection = function(x,z,gap)
        local gMax = MAX_GRADIENT
        for d = 1, gap do
            local g = (GetTerrainHeight(x,z+d-1) - GetTerrainHeight(x,z+d))
            if -gMax > g or g > gMax then
                return false
            end
        end
        for d = 1, gap-1 do
            local g = (GetTerrainHeight(x,z+d) - GetTerrainHeight(x+1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
            local g = (GetTerrainHeight(x,z+d) - GetTerrainHeight(x-1,z+d))
            if -gMax > g or g > gMax then
                return false
            end
        end
        return true
    end,
}

GameMap = Class({
    InitMap = function(self)
        self.initialised = true
        LOG('GammaAI framework: CreateMapMarkers() started!')
        local START = GetSystemTimeSecondsOnlyForProfileUse()
        self:CreateMapMarkers()
        self.zoneSets = {}
        self.numZoneSets = 0
        self.markerCounts = {}
        self:GetMarkerComponents()
        local END = GetSystemTimeSecondsOnlyForProfileUse()
        LOG(string.format('GammaAI framework: CreateMapMarkers() finished, runtime: %.2f seconds.', END - START ))
        local drawStuffz = false
        if drawStuffz then
            ForkThread(
                function()
                    local zoneSetCopy = self:GetZoneSet('ExampleZoneSet',1)
                    coroutine.yield(100)
                    while true do
                        --self:DrawLayer(3)
                        self:DrawZones(zoneSetCopy.index)
                        zoneSetCopy:DrawZones()
                        WaitTicks(2)
                    end
                end
            )
        end
    end,

    IsInitialised = function(self) return self.initialised end

    CreateMapMarkers = function(self)
        -- Step 1: Initialise arrays of points to the correct size, and record offsets for position translation
        local area = (PLAYABLE_AREA[3]-PLAYABLE_AREA[1]) * (PLAYABLE_AREA[4]-PLAYABLE_AREA[2])
        self.gap = math.max(MIN_GAP,math.ceil(math.sqrt(area/TARGET_MARKERS)))
        self.markers = {}
        self.components = {}
        self.componentNumbers = { 0, 0, 0, 0 }
        self.componentSizes = { {}, {}, {}, {} }
        self.zones = {}
        self.xSize = math.floor((PLAYABLE_AREA[3]-PLAYABLE_AREA[1])/self.gap)
        self.zSize = math.floor((PLAYABLE_AREA[4]-PLAYABLE_AREA[2])/self.gap)
        for i = 1, self.xSize do
            self.markers[i] = {}
            self.components[i] = {}
            self.zones[i] = {}
            for j = 1, self.zSize do
                -- [(+1,0), (+1,+1), (0,+1), (-1,+1), (-1,0), (-1,-1), (0,-1), (+1,-1)]
                self.markers[i][j] = {
                    { false, false, false, false, false, false, false, false }, -- Land
                    { false, false, false, false, false, false, false, false }, -- Navy
                    { false, false, false, false, false, false, false, false }, -- Hover
                    { false, false, false, false, false, false, false, false }, -- Amphibious
                }
                -- [Land, Navy, Hover, Amphibious]
                self.components[i][j] = { 0, 0, 0, 0 }
                self.zones[i][j] = {}
            end
        end
        -- Step 2: Generate connections
        self:GenerateConnections()
        -- Step 3: Generate connected components
        self:GenerateConnectedComponents()
    end,
    GenerateConnections = function(self)
        local markers = self.markers
        local gap = self.gap
        local x0 = PLAYABLE_AREA[1]
        local z0 = PLAYABLE_AREA[2]
        local CLC0 = ConnectivityCheckingFunctions.LandXDirection
        local CLC1 = ConnectivityCheckingFunctions.LandZDirection
        local CNC0 = ConnectivityCheckingFunctions.NavalXDirection
        local CNC1 = ConnectivityCheckingFunctions.NavalZDirection
        local CHC0 = ConnectivityCheckingFunctions.HoverXDirection
        local CHC1 = ConnectivityCheckingFunctions.HoverZDirection
        local CAC0 = ConnectivityCheckingFunctions.AmphibiousXDirection
        local CAC1 = ConnectivityCheckingFunctions.AmphibiousZDirection
        -- Declare some variables now that we'll need later, save us creating lots of little local variables.
        local x = 0
        local z = 0
        local _mi = nil
        local _mi1 = nil
        local _mij = nil
        local _mi1j = nil
        local _mij1 = nil
        local _mi1j1 = nil
        local land = false
        local navy = false
        local hover = false
        local amph = false
        -- [(+1, 0), (-1, 0)]
        for i = 1, self.xSize-1 do
            x = x0 - gap + i*gap
            _mi = markers[i]
            _mi1 = markers[i+1]
            for j = 1, self.zSize do
                _mij = _mi[j]
                _mi1j = _mi1[j]
                z = z0 - gap + j*gap
                land = CLC0(x,z,gap)
                navy = CNC0(x,z,gap)
                hover = CHC0(x,z,gap)
                amph = CAC0(x,z,gap)
                _mij[LAYER_LAND][1] = land
                _mi1j[LAYER_LAND][5] = land
                _mij[LAYER_NAVY][1] = navy
                _mi1j[LAYER_NAVY][5] = navy
                _mij[LAYER_HOVER][1] = hover
                _mi1j[LAYER_HOVER][5] = hover
                _mij[LAYER_AMPH][1] = amph
                _mi1j[LAYER_AMPH][5] = amph
            end
        end
        -- [(0, +1), (0,-1)]
        for i = 1, self.xSize do
            x = x0 - gap + i*gap
            _mi = markers[i]
            for j = 1, self.zSize-1 do
                _mij = _mi[j]
                _mij1 = _mi[j+1]
                z = z0 - gap + j*gap
                land = CLC1(x,z,gap)
                navy = CNC1(x,z,gap)
                hover = CHC1(x,z,gap)
                amph = CAC1(x,z,gap)
                _mij[LAYER_LAND][3] = land
                _mij1[LAYER_LAND][7] = land
                _mij[LAYER_NAVY][3] = navy
                _mij1[LAYER_NAVY][7] = navy
                _mij[LAYER_HOVER][3] = hover
                _mij1[LAYER_HOVER][7] = hover
                _mij[LAYER_AMPH][3] = amph
                _mij1[LAYER_AMPH][7] = amph
            end
        end
        -- [(+1, -1), (-1, +1)]
        for i = 1, self.xSize-1 do
            _mi = markers[i]
            _mi1 = markers[i+1]
            for j = 2, self.zSize do
                _mij = _mi[j]
                _mi1j = _mi1[j]
                _mij1 = _mi[j-1]
                _mi1j1 = _mi1[j-1]
                land = _mij[LAYER_LAND][1] and _mij[LAYER_LAND][7] and _mi1j[LAYER_LAND][7] and _mij1[LAYER_LAND][1]
                navy = _mij[LAYER_NAVY][1] and _mij[LAYER_NAVY][7] and _mi1j[LAYER_NAVY][7] and _mij1[LAYER_NAVY][1]
                hover = _mij[LAYER_HOVER][1] and _mij[LAYER_HOVER][7] and _mi1j[LAYER_HOVER][7] and _mij1[LAYER_HOVER][1]
                amph = _mij[LAYER_AMPH][1] and _mij[LAYER_AMPH][7] and _mi1j[LAYER_AMPH][7] and _mij1[LAYER_AMPH][1]
                _mij[LAYER_LAND][8] = land
                _mi1j1[LAYER_LAND][4] = land
                _mij[LAYER_NAVY][8] = navy
                _mi1j1[LAYER_NAVY][4] = navy
                _mij[LAYER_HOVER][8] = hover
                _mi1j1[LAYER_HOVER][4] = hover
                _mij[LAYER_AMPH][8] = amph
                _mi1j1[LAYER_AMPH][4] = amph
            end
        end
        -- [(+1, +1), (-1, -1)]
        for i = 1, self.xSize-1 do
            _mi = markers[i]
            _mi1 = markers[i+1]
            for j = 1, self.zSize-1 do
                _mij = _mi[j]
                _mi1j = _mi1[j]
                _mij1 = _mi[j+1]
                _mi1j1 = _mi1[j+1]
                land = _mij[LAYER_LAND][1] and _mij[LAYER_LAND][3] and _mi1j[LAYER_LAND][3] and _mij1[LAYER_LAND][1]
                navy = _mij[LAYER_NAVY][1] and _mij[LAYER_NAVY][3] and _mi1j[LAYER_NAVY][3] and _mij1[LAYER_NAVY][1]
                hover = _mij[LAYER_HOVER][1] and _mij[LAYER_HOVER][3] and _mi1j[LAYER_HOVER][3] and _mij1[LAYER_HOVER][1]
                amph = _mij[LAYER_AMPH][1] and _mij[LAYER_AMPH][3] and _mi1j[LAYER_AMPH][3] and _mij1[LAYER_AMPH][1]
                _mij[LAYER_LAND][2] = land
                _mi1j1[LAYER_LAND][6] = land
                _mij[LAYER_NAVY][2] = navy
                _mi1j1[LAYER_NAVY][6] = navy
                _mij[LAYER_HOVER][2] = hover
                _mi1j1[LAYER_HOVER][6] = hover
                _mij[LAYER_AMPH][2] = amph
                _mi1j1[LAYER_AMPH][6] = amph
            end
        end
    end,
    GenerateConnectedComponents = function(self)
        local markers = self.markers
        -- Initialise markers that have at least one connection.  Unitialised markers have component 0, which we will ignore later.
        for i = 1, self.xSize do
            local _mi = markers[i]
            for j = 1, self.zSize do
                local _mij = _mi[j]
                for k = 1, NUM_LAYERS do
                    local _mijk = _mij[k]
                    -- Init if a connection exists
                    if _mijk[1] or _mijk[2] or _mijk[3] or _mijk[4] or _mijk[5] or _mijk[6] or _mijk[7] or _mijk[8] then
                        self.components[i][j][k] = -1
                    end
                end
            end
        end
        -- Generate a component for each uninitialised marker
        for i = 1, self.xSize do
            for j = 1, self.zSize do
                for k = 1, NUM_LAYERS do
                    if self.components[i][j][k] < 0 then
                        self.componentNumbers[k] = self.componentNumbers[k]+1
                        self.componentSizes[k][self.componentNumbers[k]] = 0
                        self:GenerateComponent(i,j,k,self.componentNumbers[k])
                    end
                end
            end
        end
    end,
    GenerateComponent = function(self,i0,j0,k,componentNumber)
        local work = {{i0,j0}}
        local workLen = 1
        local i = 0
        local j = 0
        local _mij = nil
        self.components[i0][j0][k] = componentNumber
        self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
        while workLen > 0 do
            i = work[workLen][1]
            j = work[workLen][2]
            workLen = workLen-1
            _mij = self.markers[i][j][k]
            -- Since diagonal connections are purely derived from square connections, I won't bother with them for component generation
            if _mij[1] and (self.components[i+1][j][k] < 0) then
                workLen = workLen+1
                work[workLen] = {i+1,j}
                self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
                self.components[i+1][j][k] = componentNumber
            end
            if _mij[3] and (self.components[i][j+1][k] < 0) then
                workLen = workLen+1
                work[workLen] = {i,j+1}
                self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
                self.components[i][j+1][k] = componentNumber
            end
            if _mij[5] and (self.components[i-1][j][k] < 0) then
                workLen = workLen+1
                work[workLen] = {i-1,j}
                self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
                self.components[i-1][j][k] = componentNumber
            end
            if _mij[7] and (self.components[i][j-1][k] < 0) then
                workLen = workLen+1
                work[workLen] = {i,j-1}
                self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
                self.components[i][j-1][k] = componentNumber
            end
        end
    end,
    GetMarkerComponents = function(self)
        for _, item in MYOWNMARKERS do
            item.components = {}
            item.components[LAYER_LAND] = self:GetComponent(item.position, LAYER_LAND)
            item.components[LAYER_NAVY] = self:GetComponent(item.position, LAYER_NAVY)
            item.components[LAYER_HOVER] = self:GetComponent(item.position, LAYER_HOVER)
            item.components[LAYER_AMPH] = self:GetComponent(item.position, LAYER_AMPH)
        end
        self:AddMarker(item)
    end,
    AddMarker = function(self,item)
        if not self.markerCounts[item.type] then
            self.markerCounts[item.type] = {{}, {}, {}, {}}
        end
        if not self.markerCounts[item.type][LAYER_LAND] then
            self.markerCounts[item.type][LAYER_LAND] = 0
        end
        self.markerCounts[item.type][LAYER_LAND] = self.markerCounts[item.type][LAYER_LAND] + 1
        if not self.markerCounts[item.type][LAYER_NAVY] then
            self.markerCounts[item.type][LAYER_NAVY] = 0
        end
        self.markerCounts[item.type][LAYER_NAVY] = self.markerCounts[item.type][LAYER_NAVY] + 1
        if not self.markerCounts[item.type][LAYER_HOVER] then
            self.markerCounts[item.type][LAYER_HOVER] = 0
        end
        self.markerCounts[item.type][LAYER_HOVER] = self.markerCounts[item.type][LAYER_HOVER] + 1
        if not self.markerCounts[item.type][LAYER_AMPH] then
            self.markerCounts[item.type][LAYER_AMPH] = 0
        end
        self.markerCounts[item.type][LAYER_AMPH] = self.markerCounts[item.type][LAYER_AMPH] + 1
    end,
    GetSignificantComponents = function(self,minSize,layer)
        local res = {}
        for i=1, self.componentNumbers[layer] do
            if (self.componentSizes[layer][i] > minSize) or (self.markerCounts["Mass"][layer] > 0) then
                table.insert(res, i)
            end
        end
        return res
    end,
    CanPathTo = function(self,pos0,pos1,layer)
        local i0 = self:GetI(pos0[1])
        local j0 = self:GetJ(pos0[3])
        local i1 = self:GetI(pos1[1])
        local j1 = self:GetJ(pos1[3])
        return (self.components[i0][j0][layer] > 0) and (self.components[i0][j0][layer] == self.components[i1][j1][layer])
    end,
    UnitCanPathTo = function(self,unit,pos)
        local layer = self:TranslateMovementLayer(unit:GetBlueprint().Physics.MotionType)
        if layer == LAYER_NONE then
            return false
        elseif layer == LAYER_AIR then
            return true
        else
            local unitPos = unit:GetPosition()
            return self:CanPathTo(unitPos,pos,layer)
        end
    end,
    GetMovementLayer = function(self,unit)
        return self:TranslateMovementLayer(unit:GetBlueprint().Physics.MotionType)
    end,
    TranslateMovementLayer = function(self,motionType)
        -- -1 => cannot move, 0 => air unit, otherwise chooses best matching layer index
        if (not motionType) or motionType == "RULEUMT_None" then
            return LAYER_NONE
        elseif motionType == "RULEUMT_Air" then
            return LAYER_AIR
        elseif (motionType == "RULEUMT_Land") or (motionType == "RULEUMT_Biped") then
            return LAYER_LAND
        elseif motionType == "RULEUMT_Water" then
            return LAYER_NAVY
        elseif (motionType == "RULEUMT_Hover") or (motionType == "RULEUMT_AmphibiousFloating") then
            return LAYER_HOVER
        elseif motionType == "RULEUMT_Amphibious" then
            return LAYER_AMPH
        elseif motionType == "RULEUMT_SurfacingSub" then
            -- Use navy layer since required required water clearance is the same
            return LAYER_NAVY
        else
            WARN("Unknown layer type found in map:TranslateMovementLayer - "..tostring(motionType))
            return LAYER_NONE
        end
    end,
    GetMostRestrictiveMovementLayer = function(self, layer0, layer1)
        local minLayer = math.min(layer0, layer1)
        layer1 = math.max(layer0, layer1)
        if minLayer == LAYER_NONE then
            -- Something cannot move, so return that it cannot move
            return LAYER_NONE
        elseif minLayer == LAYER_AIR then
            -- Something is an air unit, so return the other movement layer
            return layer1
        elseif minLayer == LAYER_LAND then
            if layer1 == LAYER_NAVY then
                -- Land unit and naval unit, cannot move together
                return LAYER_NONE
            else
                -- Land unit and one of {land, hover, amphibous}, return land
                return LAYER_LAND
            end
        elseif minLayer == LAYER_NAVY then
            -- Combination of navy and one of {hover, amphibious}, return navy
            -- NOTE: POTENTIAL BUG HERE - amphibious + navy is being treated as navy, but amphibious units (seafloor units) might not be able to go to all navy areas due to terrain.
            -- Doesn't make sense to solve this by having a separate amphibious + water layer, nor does it make sense to return LAYER_NONE.
            return LAYER_NAVY
        else
            -- layers are both from {hover, amph}, return the larger
            return layer1
        end
    end,
    GetComponent = function(self,pos,layer)
        local i = self:GetI(pos[1])
        local j = self:GetJ(pos[3])
        return self.components[i][j][layer]
    end,
    GetComponentSize = function(self,component,layer)
        if component > 0 then
            return self.componentSizes[layer][component]
        else
            return 0
        end
    end,
    PaintZones = function(self,zoneList,index,layer)
        local edges = {}
        for i = 1, self.xSize do
            for j = 1, self.zSize do
                self.zones[i][j][index] = {-1,0}
            end
        end
        local work = CreatePriorityQueue()
        for _, zone in zoneList do
            local i = self:GetI(zone.pos[1])
            local j = self:GetJ(zone.pos[3])
            if self.components[i][j][layer] > 0 then
                work:Queue({priority=0, id=zone.id, i=i, j=j})
                zone.fail = false
            else
                zone.fail = true
            end
            edges[zone.id] = {}
        end
        while work:Size() > 0 do
            local item = work:Dequeue()
            local i = item.i
            local j = item.j
            local id = item.id
            if self.zones[i][j][index][1] < 0 then
                -- Update and iterate
                self.zones[i][j][index][1] = item.id
                self.zones[i][j][index][2] = item.priority
                if self.markers[i][j][layer][1] then
                    work:Queue({priority=item.priority+1,i=i+1,j=j,id=id})
                end
                if self.markers[i][j][layer][2] then
                    work:Queue({priority=item.priority+SQRT_2,i=i+1,j=j+1,id=id})
                end
                if self.markers[i][j][layer][3] then
                    work:Queue({priority=item.priority+1,i=i,j=j+1,id=id})
                end
                if self.markers[i][j][layer][4] then
                    work:Queue({priority=item.priority+SQRT_2,i=i-1,j=j+1,id=id})
                end
                if self.markers[i][j][layer][5] then
                    work:Queue({priority=item.priority+1,i=i-1,j=j,id=id})
                end
                if self.markers[i][j][layer][6] then
                    work:Queue({priority=item.priority+SQRT_2,i=i-1,j=j-1,id=id})
                end
                if self.markers[i][j][layer][7] then
                    work:Queue({priority=item.priority+1,i=i,j=j-1,id=id})
                end
                if self.markers[i][j][layer][8] then
                    work:Queue({priority=item.priority+SQRT_2,i=i+1,j=j-1,id=id})
                end
            elseif self.zones[i][j][index][1] ~= id then
                -- Add edge
                local dist = item.priority+self.zones[i][j][index][2]
                if not edges[self.zones[i][j][index][1]][id] then
                    edges[self.zones[i][j][index][1]][id] = {0, dist, i, j}
                    edges[id][self.zones[i][j][index][1]] = {0, dist, i, j}
                end
                edges[self.zones[i][j][index][1]][id][1] = edges[self.zones[i][j][index][1]][id][1] + 1
                edges[id][self.zones[i][j][index][1]][1] = edges[id][self.zones[i][j][index][1]][1] + 1
                if dist < edges[self.zones[i][j][index][1]][id][2] then
                    edges[self.zones[i][j][index][1]][id][2] = dist
                    edges[self.zones[i][j][index][1]][id][3] = i
                    edges[self.zones[i][j][index][1]][id][4] = j
                    edges[id][self.zones[i][j][index][1]][2] = dist
                    edges[id][self.zones[i][j][index][1]][3] = i
                    edges[id][self.zones[i][j][index][1]][4] = j
                end
            end
        end
        local edgeList = {}
        for id0, v0 in edges do
            for id1, v1 in v0 do
                if id0 < id1 then
                    local x = self:GetX(v1[3])
                    local z = self:GetZ(v1[4])
                    local y = nil
                    if layer < 4 then
                        y = GetSurfaceHeight(x,z)
                    else
                        y = GetTerrainHeight(x,z)
                    end
                    table.insert(edgeList,{zones={id0,id1},border=v1[1],distance=v1[2],midpoint={x, y, z}})
                end
            end
        end
        return edgeList
    end,
    GetZoneID = function(self,pos,index)
        local i = self:GetI(pos[1])
        local j = self:GetJ(pos[3])
        return self.zones[i][j][index][1]
    end,
    AddZoneSet = function(self,ZoneSetClass)
        self.numZoneSets = self.numZoneSets + 1
        local zoneSet = ZoneSetClass()
        zoneSet:Init(self.numZoneSets)
        zoneSet:GenerateZoneList()
        self.zoneSets[self.numZoneSets] = zoneSet
        local zones = zoneSet:GetZones()
        local edges = self:PaintZones(zones,self.numZoneSets,zoneSet.layer)
        zoneSet:AddEdges(edges)
        return self.numZoneSets
    end,
    GetZoneSet = function(self, name, layer)
        for _, zoneSet in self.zoneSets do
            if (zoneSet.name == name) and (zoneSet.layer == layer) then
                return self.zoneSets[zoneSet.index]:GetCopy()
            end
        end
        return nil
    end,
    GetZoneSetIndex = function(name, layer)
        for _, zoneSet in self.zoneSets do
            if (zoneSet.name == name) and (zoneSet.layer == layer) then
                return zoneSet.index
            end
        end
        return nil
    end,
    GetI = function(self,x)
        return math.min(math.max(math.floor((x - PLAYABLE_AREA[1])/self.gap + 1.5),1),self.xSize)
    end,
    GetJ = function(self,z)
        return math.min(math.max(math.floor((z - PLAYABLE_AREA[2])/self.gap + 1.5),1),self.zSize)
    end,
    GetX = function(self,i)
        return PLAYABLE_AREA[1] - self.gap + (i*self.gap)
    end,
    GetZ = function(self,j)
        return PLAYABLE_AREA[2] - self.gap + (j*self.gap)
    end,

    DrawZones = function(self,index)
        local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
        local gap = self.gap
        local x0 = PLAYABLE_AREA[1] - gap
        local z0 = PLAYABLE_AREA[2] - gap
        local layer = self.zoneSets[index].layer
        for i=1,self.xSize do
            local x = x0 + (i*gap)
            for j=1,self.zSize do
                local z = z0 + (j*gap)
                for k=1,8 do
                    if self.markers[i][j][layer][k] and (self.zones[i][j][index][1] > 0) then
                        local x1 = x
                        local z1 = z
                        local draw = true
                        if k == 1 then
                            x1 = x+gap
                            draw = self.zones[i][j][index][1] == self.zones[i+1][j][index][1]
                        elseif k == 2 then
                            x1 = x+gap
                            z1 = z+gap
                            draw = self.zones[i][j][index][1] == self.zones[i+1][j+1][index][1]
                        elseif k == 3 then
                            z1 = z+gap
                            draw = self.zones[i][j][index][1] == self.zones[i][j+1][index][1]
                        elseif k == 4 then
                            x1 = x-gap
                            z1 = z+gap
                            draw = self.zones[i][j][index][1] == self.zones[i-1][j+1][index][1]
                        elseif k == 5 then
                            x1 = x-gap
                            draw = self.zones[i][j][index][1] == self.zones[i-1][j][index][1]
                        elseif k == 6 then
                            x1 = x-gap
                            z1 = z-gap
                            draw = self.zones[i][j][index][1] == self.zones[i-1][j-1][index][1]
                        elseif k == 7 then
                            z1 = z-gap
                            draw = self.zones[i][j][index][1] == self.zones[i][j-1][index][1]
                        else
                            x1 = x+gap
                            z1 = z-gap
                            draw = self.zones[i][j][index][1] == self.zones[i+1][j-1][index][1]
                        end
                        if draw then
                            DrawLine({x,GetSurfaceHeight(x,z),z},{x1,GetSurfaceHeight(x1,z1),z1},colours[math.mod(self.zones[i][j][index][1],10)+1])
                        end
                    end
                end
            end
        end
    end,
    DrawLayer = function(self,layer)
        local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
        local gap = self.gap
        local x0 = PLAYABLE_AREA[1] - gap
        local z0 = PLAYABLE_AREA[2] - gap
        for i=1,self.xSize do
            local x = x0 + i*gap
            for j=1,self.zSize do
                if self.componentSizes[layer][self.components[i][j][layer]] < 50 then
                    continue
                end
                local z = z0 + j*gap
                for k=1,8 do
                    if self.markers[i][j][layer][k] then
                        local x1 = x
                        local z1 = z
                        if k == 1 then
                            x1 = x+gap
                        elseif k == 2 then
                            x1 = x+gap
                            z1 = z+gap
                        elseif k == 3 then
                            z1 = z+gap
                        elseif k == 4 then
                            x1 = x-gap
                            z1 = z+gap
                        elseif k == 5 then
                            x1 = x-gap
                        elseif k == 6 then
                            x1 = x-gap
                            z1 = z-gap
                        elseif k == 7 then
                            z1 = z-gap
                        else
                            x1 = x+gap
                            z1 = z-gap
                        end
                        DrawLine({x,GetSurfaceHeight(x,z),z},{x1,GetSurfaceHeight(x1,z1),z1},colours[math.mod(self.components[i][j][layer],10)+1])
                    end
                end
            end
        end
    end,
})

local map = GameMap()
local zoneSets = {}

function BeginSession()
    -- TODO: Detect if a map is required (inc versioning?)
    if not PLAYABLE_AREA then
        PLAYABLE_AREA = { DEFAULT_BORDER, DEFAULT_BORDER, ScenarioInfo.size[1], ScenarioInfo.size[2] }
    end
    -- Initialise map: do grid connections, generate components
    map:InitMap()
    -- Now to attempt to load any custom zone set classes
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    local customZoneSets = import('/mods/DilliDalli/lua/GammaAI/framework/mapping/Zones.lua').LoadCustomZoneSets()
    if table.getn(customZoneSets) > 0 then
        for _, ZoneSetClass in customZoneSets do
            map:AddZoneSet(ZoneSetClass)
        end
        local END = GetSystemTimeSecondsOnlyForProfileUse()
        LOG(string.format('GammaAI framework: Custom zone generation finished (%d found), runtime: %.2f seconds.', table.getn(customZoneSets), END - START ))
    else
        LOG("GammaAI framework: No custom zoning classes found.")
    end
end

function GetMap()
    return map
end