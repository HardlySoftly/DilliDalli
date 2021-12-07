--local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/FlowAI/framework/utils/PriorityQueue.lua').CreatePriorityQueue


--[[
    This code is largely written with performance in mind over readability.
    The justification in this case is that it represents a significant amount of work, and necessarily runs before the game starts.
    Every second here is a second the players are waiting to play.
    Previous iterations of this functionality ran in ~1 min timescales on 20x20 maps, necessitating a performance oriented re-write.
    Sorry for the inlining of functions, the repetitive code blocks, and the constant localling of variables :)
  ]]

TARGET_MARKERS = 180000
MIN_GAP = 5
MAX_GRADIENT = 0.5
SHIP_CLEARANCE = 1.0
SQRT_2 = math.sqrt(2)

-- Land
function CheckLandConnectivity0(x,z,gap)
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
end
function CheckLandConnectivity1(x,z,gap)
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
end
-- Naval / water surface
function CheckNavalConnectivity0(x,z,gap)
    if GetTerrainHeight(x,z) >= GetSurfaceHeight(x,z)-SHIP_CLEARANCE then
        return false
    end
    for d = 1, gap do
        -- No need for gradient checks
        if GetTerrainHeight(x+d-1,z) >= GetSurfaceHeight(x+d-1,z)-SHIP_CLEARANCE then
            return false
        end
    end
    return true
end
function CheckNavalConnectivity1(x,z,gap)
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
end
-- Hover
function CheckHoverConnectivity0(x,z,gap)
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
end
function CheckHoverConnectivity1(x,z,gap)
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
end
-- Amphibious
function CheckAmphibiousConnectivity0(x,z,gap)
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
end
function CheckAmphibiousConnectivity1(x,z,gap)
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
end
--[[ TODO: subs
function CheckLandConnectivity0(x,z,gap)
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
end
function CheckLandConnectivity1(x,z,gap)
    local gMax = MAX_GRADIENT
    if GetTerrainHeight(x,z) < GetSurfaceHeight(x,z) then
        return false
    end
    for d = 1, gap do
        local g = (GetTerrainHeight(x,z+d-1) - GetTerrainHeight(x,z+d))
        if -gMax > g or g > gMax then
            return false
        end
        if GetTerrainHeight(x+d-1,z) < GetSurfaceHeight(x+d-1,z) then
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
end]]

GameMap = Class({
    InitMap = function(self)
        LOG('FlowAI framework: CreateMapMarkers() started!')
        local START = GetSystemTimeSecondsOnlyForProfileUse()
        self:CreateMapMarkers()
        self.zoneSets = {}
        self.numZoneSets = 0
        local END = GetSystemTimeSecondsOnlyForProfileUse()
        LOG(string.format('FlowAI framework: CreateMapMarkers() finished, runtime: %.2f seconds.', END - START ))
        local drawStuffz = false
        if drawStuffz then
            ForkThread(
                function()
                    local zoneSetCopy = self:GetZoneSet('LayerZoneSet',1)
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

    CreateMapMarkers = function(self)
        -- Step 1: Initialise arrays of points to the correct size, and record offsets for position translation
        local area = (PLAYABLE_AREA[3]-PLAYABLE_AREA[1]) * (PLAYABLE_AREA[4]-PLAYABLE_AREA[2])
        self.gap = math.max(MIN_GAP,math.ceil(math.sqrt(area/TARGET_MARKERS)))
        self.markers = {}
        self.components = {}
        self.componentNumbers = { 0, 0, 0, 0, 0 }
        self.componentSizes = { {}, {}, {}, {}, {} }
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
                    { false, false, false, false, false, false, false, false }  -- Submarine
                }
                -- [Land, Navy, Hover, Amphibious, Submarine]
                self.components[i][j] = { 0, 0, 0, 0, 0 }
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
        local CLC0 = CheckLandConnectivity0
        local CLC1 = CheckLandConnectivity1
        local CNC0 = CheckNavalConnectivity0
        local CNC1 = CheckNavalConnectivity1
        local CHC0 = CheckHoverConnectivity0
        local CHC1 = CheckHoverConnectivity1
        local CAC0 = CheckAmphibiousConnectivity0
        local CAC1 = CheckAmphibiousConnectivity1
        -- [(+1, 0), (-1, 0)]
        for i = 1, self.xSize-1 do
            local x = x0 - gap + i*gap
            local _mi = markers[i]
            local _mi1 = markers[i+1]
            for j = 1, self.zSize do
                local _mij = _mi[j]
                local _mi1j = _mi1[j]
                local z = z0 - gap + j*gap
                local land = CLC0(x,z,gap)
                local navy = CNC0(x,z,gap)
                local hover = CHC0(x,z,gap)
                local amph = CAC0(x,z,gap)
                _mij[1][1] = land
                _mi1j[1][5] = land
                _mij[2][1] = navy
                _mi1j[2][5] = navy
                _mij[3][1] = hover
                _mi1j[3][5] = hover
                _mij[4][1] = amph
                _mi1j[4][5] = amph
            end
        end
        -- [(0, +1), (0,-1)]
        for i = 1, self.xSize do
            local x = x0 - gap + i*gap
            local _mi = markers[i]
            for j = 1, self.zSize-1 do
                local _mij = _mi[j]
                local _mij1 = _mi[j+1]
                local z = z0 - gap + j*gap
                local land = CLC1(x,z,gap)
                local navy = CNC1(x,z,gap)
                local hover = CHC1(x,z,gap)
                local amph = CAC1(x,z,gap)
                _mij[1][3] = land
                _mij1[1][7] = land
                _mij[2][3] = navy
                _mij1[2][7] = navy
                _mij[3][3] = hover
                _mij1[3][7] = hover
                _mij[4][3] = amph
                _mij1[4][7] = amph
            end
        end
        -- [(+1, -1), (-1, +1)]
        for i = 1, self.xSize-1 do
            local _mi = markers[i]
            local _mi1 = markers[i+1]
            for j = 2, self.zSize do
                local _mij = _mi[j]
                local _mi1j = _mi1[j]
                local _mij1 = _mi[j-1]
                local _mi1j1 = _mi1[j-1]
                local land = _mij[1][1] and _mij[1][7] and _mi1j[1][7] and _mij1[1][1]
                local navy = _mij[2][1] and _mij[2][7] and _mi1j[2][7] and _mij1[2][1]
                local hover = _mij[3][1] and _mij[3][7] and _mi1j[3][7] and _mij1[3][1]
                local amph = _mij[4][1] and _mij[4][7] and _mi1j[4][7] and _mij1[4][1]
                _mij[1][8] = land
                _mi1j1[1][4] = land
                _mij[2][8] = navy
                _mi1j1[2][4] = navy
                _mij[3][8] = hover
                _mi1j1[3][4] = hover
                _mij[4][8] = amph
                _mi1j1[4][4] = amph
            end
        end
        -- [(+1, +1), (-1, -1)]
        for i = 1, self.xSize-1 do
            local _mi = markers[i]
            local _mi1 = markers[i+1]
            for j = 1, self.zSize-1 do
                local _mij = _mi[j]
                local _mi1j = _mi1[j]
                local _mij1 = _mi[j+1]
                local _mi1j1 = _mi1[j+1]
                local land = _mij[1][1] and _mij[1][3] and _mi1j[1][3] and _mij1[1][1]
                local navy = _mij[2][1] and _mij[2][3] and _mi1j[2][3] and _mij1[2][1]
                local hover = _mij[3][1] and _mij[3][3] and _mi1j[3][3] and _mij1[3][1]
                local amph = _mij[4][1] and _mij[4][3] and _mi1j[4][3] and _mij1[4][1]
                _mij[1][2] = land
                _mi1j1[1][6] = land
                _mij[2][2] = navy
                _mi1j1[2][6] = navy
                _mij[3][2] = hover
                _mi1j1[3][6] = hover
                _mij[4][2] = amph
                _mi1j1[4][6] = amph
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
                for k = 1, 5 do
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
                for k = 1, 5 do
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
        self.components[i0][j0][k] = componentNumber
        self.componentSizes[k][componentNumber] = self.componentSizes[k][componentNumber] + 1
        while workLen > 0 do
            local i = work[workLen][1]
            local j = work[workLen][2]
            workLen = workLen-1
            local _mij = self.markers[i][j][k]
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
    CanPathTo = function(self,pos0,pos1,layer)
        local i0 = self:GetI(pos0[1])
        local j0 = self:GetJ(pos0[3])
        local i1 = self:GetI(pos1[1])
        local j1 = self:GetJ(pos1[3])
        return (self.components[i0][j0][layer] > 0) and (self.components[i0][j0][layer] == self.components[i1][j1][layer])
    end,
    UnitCanPathTo = function(self,unit,pos)
        local layer = self:GetMovementLayer(unit)
        if layer == -1 then
            return false
        elseif layer == 0 then
            return true
        else
            local unitPos = unit:GetPosition()
            return self:CanPathTo(unitPos,pos,layer)
        end
    end,
    GetMovementLayer = function(self,unit)
        -- -1 => cannot move, 0 => air unit, otherwise chooses best matching layer index
        local motionType = unit:GetBlueprint().Physics.MotionType
        if (not motionType) or motionType == "RULEUMT_None" then
            return -1
        elseif motionType == "RULEUMT_Air" then
            return 0
        elseif motionType == "RULEUMT_Land" then
            return 1
        elseif motionType == "RULEUMT_Water" then
            return 2
        elseif (motionType == "RULEUMT_Hover") or (motionType == "RULEUMT_AmphibiousFloating") then
            return 3
        elseif "RULEUMT_Amphibious" then
            return 4
        elseif motionType == "RULEUMT_SurfacingSub" then
            return 5
        else
            WARN("Unknown layer type found in map:GetMovementLayer - "..tostring(motionType))
            return -1
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
            local j = self:GetI(zone.pos[3])
            if self.components[i][j][layer] > 0 then
                work:Queue({priority=0, id=zone.id, i=i, j=j})
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
                    edges[self.zones[i][j][index][1]][id] = {0, dist}
                    edges[id][self.zones[i][j][index][1]] = {0, dist}
                end
                edges[self.zones[i][j][index][1]][id][1] = edges[self.zones[i][j][index][1]][id][1] + 1
                edges[self.zones[i][j][index][1]][id][2] = math.min(edges[self.zones[i][j][index][1]][id][2],dist)
                edges[id][self.zones[i][j][index][1]][1] = edges[id][self.zones[i][j][index][1]][1] + 1
                edges[id][self.zones[i][j][index][1]][2] = math.min(edges[id][self.zones[i][j][index][1]][2],dist)
                
            end
        end
        local edgeList = {}
        for id0, v0 in edges do
            for id1, v1 in v0 do
                if id0 < id1 then
                    table.insert(edgeList,{zones={id0,id1},border=v1[1],distance=v1[2]})
                end
            end
        end
        return edgeList
    end,
    GetZoneID = function(self,pos,index)
        local i = self:GetI(pos[1])
        local j = self:GetI(pos[3])
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

local DEFAULT_BORDER = 4
function BeginSession()
    -- TODO: Detect if a map is required (inc versioning?)
    PLAYABLE_AREA = { DEFAULT_BORDER, DEFAULT_BORDER, ScenarioInfo.size[1], ScenarioInfo.size[2] }
    map:InitMap()
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    local LayerZoneSet = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Zones.lua').LayerZoneSet
    for i=1, 5 do
        map:AddZoneSet(LayerZoneSet)
    end
    local END = GetSystemTimeSecondsOnlyForProfileUse()
    LOG(string.format('FlowAI framework: Default zone generation finished, runtime: %.2f seconds.', END - START ))
    -- Now to attempt to load any custom zone set classes
    START = GetSystemTimeSecondsOnlyForProfileUse()
    local customZoneSets = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Zones.lua').LoadCustomZoneSets()
    if table.getn(customZoneSets) > 0 then
        -- First randomise the table order.
        -- This forces people to check the ZoneSet data rather than relying on the index being forever the same (which it might not be if more mods get loaded).
        table.sort(customZoneSets,function(a,b) return Random(0,1) == 1 end)
        for _, ZoneSetClass in customZoneSets do
            map:AddZoneSet(ZoneSetClass)
        end
        END = GetSystemTimeSecondsOnlyForProfileUse()
        LOG(string.format('FlowAI framework: Custom zone generation finished, runtime: %.2f seconds.', END - START ))
    else
        LOG("FlowAI framework: No custom zoning classes found.")
    end
end

function GetMap()
    return map
end

local MYOWNFUCKINGMARKERSYOUADAPTIVEMAPPRICKS = {}

function CreateMarker(t,x,y,z,size)
    table.insert(MYOWNFUCKINGMARKERSYOUADAPTIVEMAPPRICKS,{type=t,position={x,y,z}})
end
function GetMarkers()
    return MYOWNFUCKINGMARKERSYOUADAPTIVEMAPPRICKS
end

local PLAYABLE_AREA = {}
function SetPlayableArea(x0,z0,x1,z1)
    -- Fields of Isis is a bad map, I hate to be the one who has to say it.
    PLAYABLE_AREA = { x0, z0, x1, z1 }
end