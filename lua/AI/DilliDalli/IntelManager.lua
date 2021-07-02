local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')
local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue



IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}
        self.threatTable = { land = {}, air = {} }

        self:LoadMapMarkers()
        self:FindSpawns()

        self.mme = {}
    end,

    LoadMapMarkers = function(self)
        local MAP = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').GetMap()
        self.gap = MAP.gap
        self.xOffset = MAP.xOffset
        self.zOffset = MAP.zOffset
        self.xNum = MAP.xNum
        self.zNum = MAP.zNum
        -- Get our own copy of this since we might want to edit fields in here
        self.markers = table.deepcopy(MAP.markers)
        self.zones = table.deepcopy(MAP.zones)
        for _, v in self.zones do
            v.control = {land = {enemy = 0, ally = 0}, air = {enemy = 0, ally = 0}}
        end
    end,

    FindSpawns = function(self)
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        self.allies = {}
        self.enemies = {}
        -- TODO: Respect spawn intel levels (e.g. random spawns wouldn't have this info)
        for k, v in ScenarioInfo.ArmySetup do
            local army = v
            local pos = ScenarioUtils.GetMarker(k).position
            if not pos then
                continue
            end
            if myIndex == army.ArmyIndex then
                self.spawn = table.copy(pos)
                table.insert(self.allies,table.copy(pos))
            elseif IsAlly(army.ArmyIndex,myIndex) then
                table.insert(self.allies,table.copy(pos))
            elseif IsEnemy(army.ArmyIndex,myIndex) then
                table.insert(self.enemies,table.copy(pos))
            end
        end
    end,

    GetIndices = function(self,x,z)
        local i = math.round((x-self.xOffset)/self.gap) + 1
        local j = math.round((z-self.zOffset)/self.gap) + 1
        return {math.min(math.max(1,i),self.xNum), math.min(math.max(1,j),self.zNum)}
    end,

    GetPosition = function(self,i,j)
        local x = self.xOffset + (i-1)*self.gap
        local z = self.xOffset + (j-1)*self.gap
        return {x, GetSurfaceHeight(x,z), z}
    end,

    PickBuildOrder = function(self)
        return BOs.LandLand
    end,

    EmptyMassMarkerExists = function(self,pos)
        local indices = self:GetIndices(pos[1],pos[3])
        local component = tostring(self.markers[indices[1]][indices[2]].surf.component)
        if self.mme[component] then
            return self.mme[component].exists
        else
            if self:FindNearestEmptyMarker(pos,"Mass") then
                self.mme[component] = { exists = true }
            else
                self.mme[component] = { exists = false }
            end
        end
    end,

    FindNearestEmptyMarker = function(self,pos,t)
        local start = PROFILER:Now()
        local markers = ScenarioUtils.GetMarkers()
        local best = 1000000
        local bestMarker = nil
        local bp = self.brain.aiBrain:GetUnitBlueprint('uab1103')
        -- TODO: Support different kinds of pathing
        for _, v in markers do
            if v.type == t then
                local dist = VDist3(pos,v.position)
                if dist < best and self:CanBuildOnMarker(v.position,bp)
                               and self:CanPathToSurface(pos,v.position)
                               and self.brain.base:LocationIsClear(v.position,bp) then
                    best = dist
                    bestMarker = v
                end
            end
        end
        PROFILER:Add("FindNearestEmptyMarker",PROFILER:Now()-start)
        return bestMarker
    end,

    CanBuildOnMarker = function(self,pos)
        local alliedUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Ally')
        if alliedUnits and (table.getn(alliedUnits) > 0) then
            return false
        end
        local neutralUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Neutral')
        if neutralUnits and (table.getn(neutralUnits) > 0) then
            return false
        end
        local enemyUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Enemy')
        if enemyUnits and (table.getn(enemyUnits) > 0) then
            return false
        end
        return true
    end,

    GetEnemyStructure = function(self,pos)
        local units = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Enemy')
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        if units and table.getn(units) > 0 then
            local blip = units[1]:GetBlip(myIndex)
            if blip and (blip:IsOnRadar(myIndex) or blip:IsSeenEver(myIndex)) then
                return units[1]
            end
        end
        return nil
    end,

    GetNumAvailableMassPoints = function(self)
        if self.massNumCached then
            return self.massNumCached
        end
        local num = 0
        local markers = ScenarioUtils.GetMarkers()
        for _, v in markers do
            if v.type == "Mass" and self:CanBuildOnMarker(v.position) then
                num = num + 1
            end
        end
        self.massNumCached = true
        self.massNum = num
        return num
    end,

    CanPathToSurface = function(self,pos0,pos1)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]].surf.component == self.markers[indices1[1]][indices1[2]].surf.component
    end,

    CanPathToLand = function(self,pos0,pos1)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]].land.component == self.markers[indices1[1]][indices1[2]].land.component
    end,

    FindZone = function(self,pos)
        local best = nil
        local bestDist = 0
        for _, v in self.zones do
            if (not best) or VDist3(pos,v.pos) < bestDist then
                best = v
                bestDist = VDist3(pos,v.pos)
            end
        end
        return best
    end,

    GetEnemyLandThreatInRadius = function(self, pos, radius)
        local units = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,pos,radius,'Enemy')
        return self:GetLandThreat(units)
    end,

    GetLandThreat = function(self,units)
        local totalThreat = 0
        for _, unit in units do
            totalThreat = totalThreat + self:GetUnitLandThreat(unit)
        end
        return totalThreat
    end,

    GetLandThreatAndPos = function(self,units)
        local totalThreat = 0
        local x = 0
        local z = 0
        for _, unit in units do
            local t = self:GetUnitLandThreat(unit)
            totalThreat = totalThreat + t
            local pos = unit:GetPosition()
            x = x + pos[1]
            z = z + pos[3]
        end
        if totalThreat == 0 then
            return { threat = 0, pos = nil }
        else
            x = x/totalThreat
            z = z/totalThreat
            return { threat = totalThreat, pos = {x, GetSurfaceHeight(x,z), z} }
        end
    end,

    GetUnitLandThreat = function(self,unit)
        if self.threatTable.land[unit.UnitId] then
            return self.threatTable.land[unit.UnitId]
        end
        local threat = 0
        if EntityCategoryContains(categories.COMMAND,unit) then
            threat = 20
        elseif EntityCategoryContains(categories.STRUCTURE,unit) then
            threat = 0.1
            if EntityCategoryContains(categories.DIRECTFIRE,unit) then
                threat = 5
            end
        elseif EntityCategoryContains(categories.ENGINEER,unit) then
            threat = 0.1
        elseif EntityCategoryContains(categories.LAND*categories.MOBILE,unit) then
            if EntityCategoryContains(categories.SCOUT,unit) then
                threat = 0.1
            elseif EntityCategoryContains(categories.TECH1,unit) then
                threat = 1
            elseif EntityCategoryContains(categories.TECH2,unit) then
                threat = 3
            elseif EntityCategoryContains(categories.TECH3,unit) then
                threat = 6
            elseif EntityCategoryContains(categories.EXPERIMENTAL,unit) then
                threat = 80
            end
        end
        self.threatTable.land[unit.UnitId] = threat
        return threat
    end,

    GetAirThreat = function(self,units)
        local threat = 0
        for _, unit in units do
            if EntityCategoryContains(categories.AIR*categories.MOBILE,unit) then
                threat = threat + 1
            end
        end
        return threat
    end,

    MonitorMapZones = function(self)
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        for _, v in self.zones do
            local enemies = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,v.pos,self.zoneRadius,'Enemy')
            local allies = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,v.pos,self.zoneRadius,'Ally')
            v.control.land.enemy = self:GetLandThreat(enemies)
            v.control.land.ally = self:GetLandThreat(allies)
            v.control.air.enemy = self:GetAirThreat(enemies)
            v.control.air.ally = self:GetAirThreat(allies)
        end
    end,

    MapMonitoringThread = function(self)
        local start = PROFILER:Now()
        while self.brain:IsAlive() do
            self:MonitorMapZones()
            PROFILER:Add("MapMonitoringThread",PROFILER:Now()-start)
            WaitTicks(10)
            start = PROFILER:Now()
        end
        PROFILER:Add("MapMonitoringThread",PROFILER:Now()-start)
    end,

    Run = function(self)
        self:ForkThread(self.MapMonitoringThread)
        self:ForkThread(self.CacheClearThread)
    end,

    CacheClearThread = function(self)
        while self.brain:IsAlive() do
            -- I'm not going to profile this.  Seriously.
            self.massNumCached = false
            self.mme = {}
            WaitTicks(1)
        end
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.brain.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

function CreateIntelManager(brain)
    local im = IntelManager()
    im:Initialise(brain)
    return im
end
