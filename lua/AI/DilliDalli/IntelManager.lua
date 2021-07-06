local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')
local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue
local MAP = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').GetMap()

-- Zone classes
local ALLIED = "allied"
local ENEMY = "enemy"
local CONTESTED = "contested"
local NEUTRAL = "neutral"

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}
        self.threatTable = { land = {}, air = {} }
        self.zoneRadius = 40
        self.controlSpreadSpeed = 1.4

        self:LoadMapMarkers()
        self:FindSpawns()

        self.mme = {}
    end,

    -- ========== Initital Setup Stuff ==========
    LoadMapMarkers = function(self)
        self.gap = MAP.gap
        self.xOffset = MAP.xOffset
        self.zOffset = MAP.zOffset
        self.xNum = MAP.xNum
        self.zNum = MAP.zNum
        -- Pls don't edit these markers; it's shared across all DilliDalli brains.  I could copy out but 
        self.markers = MAP.markers
        self.zones = table.deepcopy(MAP.zones)
        -- TODO: update zone edge references
        for _, v in self.zones do
            v.control = {land = {enemy = 0, ally = 0}, air = {enemy = 0, ally = 0}}
            v.intel = {
                control = {enemy = 0, allied = 0},
                latest = 0,
                threat = {land = {enemy = 0, allied = 0}, air = {enemy = 0, allied = 0}},
                importance = {enemy = 0, allied = 0}
            }
            for _, e in v.edges do
                for _, z in self.zones do
                    if z.id == e.zoneID then
                        e.zone = z
                    end
                end
            end
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
                local z = self:FindZone(pos)
                if z then
                    z.intel.enemyBase = true
                    z.intel.control.enemy = 1
                end
            end
        end
    end,
    PickBuildOrder = function(self)
        return BOs.LandLand
    end,

    -- ========== Marker Stuff ==========
    EmptyMassMarkerExists = function(self,pos)
        local indices = MAP:GetIndices(pos[1],pos[3])
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
                               and MAP:CanPathTo(pos,v.position,"surf")
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

    -- ========== Threat Stuff ==========
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
            threat = 0.01
            if EntityCategoryContains(categories.DIRECTFIRE,unit) then
                if EntityCategoryContains(categories.TECH1,unit) then
                    threat = 6
                elseif EntityCategoryContains(categories.TECH2,unit) then
                    threat = 12
                else
                    threat = 15
                end
            end
        elseif EntityCategoryContains(categories.ENGINEER,unit) then
            threat = 0.1
        elseif EntityCategoryContains(categories.LAND*categories.MOBILE,unit) then
            if EntityCategoryContains(categories.SCOUT,unit) then
                threat = 0.2
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

    -- ========== Zone Monitoring Stuff ==========
    -- Assess who controls which zones
    -- TODO: make use of threat data
    ZoneControl = function(self,zone,alliedUnits,enemyUnits)
        if zone.intel.latest == 0 then
            -- TODO: make this a bit more continuous and a bit less discrete
            if table.getn(alliedUnits) > 0 and table.getn(enemyUnits) > 0 and 2*table.getn(alliedUnits) > table.getn(enemyUnits) then
                zone.intel.control.allied = table.getn(alliedUnits)/(table.getn(alliedUnits) + table.getn(enemyUnits))
                zone.intel.control.enemy = table.getn(enemyUnits)/(table.getn(alliedUnits) + table.getn(enemyUnits))
            elseif table.getn(enemyUnits) > 0 or zone.intel.enemyBase then
                zone.intel.control.allied = 0.0
                zone.intel.control.enemy = 1.0
            elseif table.getn(alliedUnits) > 0 then
                zone.intel.control.allied = 1.0
                zone.intel.control.enemy = 0.0
            end
        else
            zone.intel.control.allied = 0
            local t = 0
            for _, e in zone.edges do
                t = math.max(t,(e.zone.intel.control.enemy-0.3)*self.controlSpreadSpeed/e.dist)
            end
            zone.intel.control.enemy = zone.intel.control.enemy + (1-zone.intel.control.enemy)*t
        end
    end,
    -- TODO: Assess importance of different zones (structure investment)
    ZoneImportance = function(self,zone,alliedUnits,enemyUnits)
        zone.intel.importance.enemy = 0
        for _, v in enemyUnits do
            if EntityCategoryContains(categories.STRUCTURE, v) then
                zone.intel.importance.enemy = zone.intel.importance.enemy + 1
            end
        end
    end,
    -- TODO: Assess threats in each zone
    ZoneThreat = function(self,zone,alliedUnits,enemyUnits)
        if zone.intel.latest == 0 then
            zone.intel.threat.land.enemy = math.max(self:GetLandThreat(enemyUnits),0.9*zone.intel.threat.land.enemy)
            zone.intel.threat.air.enemy = math.max(self:GetAirThreat(enemyUnits),0.9*zone.intel.threat.air.enemy)
        else
            zone.intel.threat.land.enemy = zone.intel.threat.land.enemy*0.99
            zone.intel.threat.air.enemy = zone.intel.threat.air.enemy*0.99
        end
        zone.intel.threat.land.allied = self:GetLandThreat(alliedUnits)
        zone.intel.threat.air.allied = self:GetAirThreat(alliedUnits)
    end,
    -- Assess when this zone was last scouted
    -- TODO: detect scouts better for improved estimates
    ZoneIntel = function(self,zone,alliedUnits,enemyUnits)
        if table.getn(alliedUnits) > 0 then
            zone.intel.latest = 0
        else
            zone.intel.latest = zone.intel.latest + 1
        end
    end,
    -- TODO: Weight zones according to importance and distances (some kind of centrality measure)
    ZoneReweighting = function(self)
    end,
    -- Classify zone based on control
    ZoneClassify = function(self,zone)
        if zone.intel.control.allied > 0.7 and (zone.intel.threat.land.allied > zone.intel.threat.land.enemy*3) and (zone.intel.importance.enemy == 0) then
            zone.intel.class = ALLIED
        elseif zone.intel.control.allied > 0.3 then
            zone.intel.class = CONTESTED
        elseif zone.intel.control.allied == 0 and zone.intel.control.enemy > 0.3 then
            zone.intel.class = ENEMY
        else
            zone.intel.class = NEUTRAL
        end
    end,
    MonitorMapZones = function(self)
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        for _, v in self.zones do
            local enemies = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,v.pos,self.zoneRadius,'Enemy')
            local allies = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,v.pos,self.zoneRadius*0.75,'Ally')
            self:ZoneIntel(v,allies,enemies)
            self:ZoneImportance(v,allies,enemies)
            self:ZoneThreat(v,allies,enemies)
            self:ZoneControl(v,allies,enemies)
            self:ZoneClassify(v)
        end
        self:ZoneReweighting()
    end,
    MapMonitoringThread = function(self)
        WaitTicks(500)
        local start = PROFILER:Now()
        while self.brain:IsAlive() do
            self:MonitorMapZones()
            PROFILER:Add("MapMonitoringThread",PROFILER:Now()-start)
            WaitTicks(10)
            start = PROFILER:Now()
        end
        PROFILER:Add("MapMonitoringThread",PROFILER:Now()-start)
    end,
    NumLandAssaultZones = function(self)
        local num = 0
        for _, z in self.zones do
            if z.intel.class == CONTESTED or z.intel.class == ENEMY then
                for _, e in z.edges do
                    if e.zone.intel.class == NEUTRAL or e.zone.intel.class == ALLIED then
                        num = num+1
                        break
                    end
                end
            end
        end
        return num
    end,
    MapDrawingThread = function(self)
        WaitTicks(30)
        local start = PROFILER:Now()
        while true do
            for _, z in self.zones do
                if z.intel.latest > 0 then
                    DrawCircle(z.pos,z.intel.latest/10,'66666666')
                end
                if z.intel.control.allied > 0 then
                    DrawCircle(z.pos,10*z.intel.control.allied,'aa44ff44')
                else
                    DrawCircle(z.pos,10,'aaffffff')
                end
                if z.intel.control.enemy > 0 then
                    DrawCircle(z.pos,10*z.intel.control.enemy,'aaff4444')
                end
                for _, e in z.edges do
                    if e.zone.id < z.id then
                        local ca1 = z.intel.control.allied > z.intel.control.enemy
                        local ca2 = e.zone.intel.control.allied > e.zone.intel.control.enemy
                        local ce1 = z.intel.control.allied <= z.intel.control.enemy and z.intel.control.enemy > 0.3
                        local ce2 = e.zone.intel.control.allied <= e.zone.intel.control.enemy and e.zone.intel.control.enemy > 0.3
                        if ca1 and ca2 then
                            -- Allied edge
                            DrawLine(z.pos,e.zone.pos,'8800ff00')
                        elseif (ca1 and ce2) or (ca2 and ce1) then
                            -- Contested edge
                            DrawLine(z.pos,e.zone.pos,'88ffff00')
                        elseif ce1 and ce2 then
                            -- Enemy edge
                            DrawLine(z.pos,e.zone.pos,'88ff0000')
                        elseif (ca1 or ca2) and (not (ce1 or ce2)) then
                            -- Allied expansion edge
                            DrawLine(z.pos,e.zone.pos,'8800ffff')
                        elseif (ce1 or ce2) and (not (ca1 or ca2)) then
                            -- Enemy expansion edge
                            DrawLine(z.pos,e.zone.pos,'88ff00ff')
                        else
                            -- Nobodies edge
                            DrawLine(z.pos,e.zone.pos,'66666666')
                        end
                    end
                end
            end
            PROFILER:Add("MapDrawingThread",PROFILER:Now()-start)
            WaitTicks(2)
            start = PROFILER:Now()
        end
    end,

    -- ========== Misc Stuff ==========
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

    Run = function(self)
        self:ForkThread(self.MapMonitoringThread)
        self:ForkThread(self.MapDrawingThread)
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
