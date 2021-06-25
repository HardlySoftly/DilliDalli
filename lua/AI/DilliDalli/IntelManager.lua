local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

R2 = math.sqrt(2)

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}
        self.zoneRadius = 30
        self.edgeMult = 1.1
        self.threatTable = { land = {}, air = {} }

        self:LoadMapMarkers()
        self:FindSpawns()
        self:GenerateMapZones()
        self:GenerateMapEdges()

        self.mme = {}
    end,

    LoadMapMarkers = function(self)
        self.gap = ScenarioInfo.DilliDalliMap.gap
        self.xOffset = ScenarioInfo.DilliDalliMap.xOffset
        self.zOffset = ScenarioInfo.DilliDalliMap.zOffset
        self.xNum = ScenarioInfo.DilliDalliMap.xNum
        self.zNum = ScenarioInfo.DilliDalliMap.zNum
        -- Get our own copy of this since we migth want to edit fields in here
        self.markers = table.deepcopy(ScenarioInfo.DilliDalliMap.markers)
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

    GetPosition = function(i,j)
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

    CreateZone = function(self,pos,weight)
        return { pos = table.copy(pos), weight = weight, control = { land = { ally = 0, enemy = 0 }, air = { ally = 0, enemy = 0 } }, edges = {} }
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

    GenerateMapZones = function(self)
        self.zones = {}
        local massPoints = {}
        for _, v in ScenarioUtils.GetMarkers() do
            if v.type == "Mass" then
                table.insert(massPoints, { pos=v.position, claimed = false, weight = 1, aggX = v.position[1], aggZ = v.position[3] })
            end
        end
        complete = (table.getn(massPoints) == 0)
        while not complete do
            complete = true
            -- Update weights
            for _, v in massPoints do
                v.weight = 1
                v.aggX = v.pos[1]
                v.aggZ = v.pos[3]
            end
            for _, v1 in massPoints do
                if not v1.claimed then
                    for _, v2 in massPoints do
                        if (not v2.claimed) and VDist3(v1.pos,v2.pos) < self.zoneRadius then
                            v1.weight = v1.weight + 1
                            v1.aggX = v1.aggX + v2.pos[1]
                            v1.aggZ = v1.aggZ + v2.pos[3]
                        end
                    end
                end
            end
            -- Find next point to add
            local best = nil
            for _, v in massPoints do
                if (not v.claimed) and ((not best) or best.weight < v.weight) then
                    best = v
                end
            end
            -- Add next point
            best.claimed = true
            local x = best.aggX/best.weight
            local z = best.aggZ/best.weight
            table.insert(self.zones,self:CreateZone({x,GetSurfaceHeight(x,z),z},best.weight))
            -- Claim nearby points
            for _, v in massPoints do
                if (not v.claimed) and VDist3(v.pos,best.pos) < self.zoneRadius then
                    v.claimed = true
                elseif not v.claimed then
                    complete = false
                end
            end
        end
    end,

    GenerateMapEdges = function(self)
        for k0, zone in self.zones do
            for k1, v1 in self.zones do
                if k1 == k0 or not self:CanPathToSurface(zone.pos,v1.pos) then
                    continue
                end
                local amClosest = true
                -- TODO: Replace VDist3 with actual distance calculations
                -- TODO: Pathability checks
                local vz1 = VDist3(v1.pos,zone.pos)/self.edgeMult - 10
                for k2, v2 in self.zones do
                    if k2 == k1 or k2 == k0  or not self:CanPathToSurface(zone.pos,v2.pos) then
                        continue
                    end
                    if VDist3(v2.pos,zone.pos) < vz1 and VDist3(v1.pos,v2.pos) < vz1 then
                        amClosest = false
                    end
                end
                if amClosest then
                    table.insert(zone.edges,v1)
                end
            end
        end
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
        while self.brain:IsAlive() do
            self:MonitorMapZones()
            WaitTicks(10)
        end
    end,

    MapDrawingThread = function(self)
        while self.brain:IsAlive() do
            for _, v in self.zones do
                DrawCircle(v.pos,5*v.weight,'aaffffff')
                DrawCircle(v.pos,v.control.land.enemy+1,'aaff2222')
                DrawCircle(v.pos,v.control.land.ally+1,'aa22ff22')
                for _, v2 in v.edges do
                    DrawLine(v.pos,v2.pos,'aa000000')
                end
            end
            WaitTicks(2)
        end
    end,

    Run = function(self)
        self:ForkThread(self.MapMonitoringThread)
        self:ForkThread(self.CacheClearThread)
        --self:ForkThread(self.MapDrawingThread)
    end,

    CacheClearThread = function(self)
        while self.brain:IsAlive() do
            self.massNumCached = false
            self.mme = {}
            WaitTicks(1)
        end
    end,

    GetNeighbours = function(self,i,j)
        res = {}
        if i < self.xNum and j < self.zNum then
            table.insert(res,{ i = i+1, j = j+1, d = R2*self.gap })
        end
        if i < self.xNum then
            table.insert(res,{ i = i+1, j = j, d = self.gap })
        end
        if i < self.xNum and j > 1 then
            table.insert(res,{ i = i+1, j = j-1, d = R2*self.gap })
        end
        if j > 1 then
            table.insert(res,{ i = i, j = j-1, d = self.gap })
        end
        if i > 1 and j > 1 then
            table.insert(res,{ i = i-1, j = j-1, d = R2*self.gap })
        end
        if i > 1 then
            table.insert(res,{ i = i-1, j = j, d = self.gap })
        end
        if i > 1 and j < self.zNum then
            table.insert(res,{ i = i-1, j = j+1, d = R2*self.gap })
        end
        if j < self.zNum then
            table.insert(res,{ i = i, j = j+1, d = self.gap })
        end
        return res
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
