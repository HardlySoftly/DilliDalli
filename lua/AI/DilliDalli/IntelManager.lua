local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

R2 = math.sqrt(2)

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}
        self.zoneRadius = 30

        self:LoadMapMarkers()
        self:GenerateMapZones()
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
        local units = GetUnitsInRect(Rect(pos[1],pos[3],pos[1],pos[3]))
        local alliedUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Ally')
        local neutralUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Neutral')
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        if (alliedUnits and table.getn(alliedUnits) > 0) or (neutralUnits and table.getn(neutralUnits) > 0) then
            return false
        end
        local enemyUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Enemy')
        if table.getn(enemyUnits) > 0 then
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
        local num = 0
        local markers = ScenarioUtils.GetMarkers()
        for _, v in markers do
            if v.type == "Mass" and self:CanBuildOnMarker(v.position) then
                num = num + 1
            end
        end
        return num
    end,

    CanPathToSurface = function(self,pos0,pos1)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]].surf.component == self.markers[indices1[1]][indices1[2]].surf.component
    end,

    CreateZone = function(self,pos,weight)
        return { pos = table.copy(pos), weight = weight, control = 0 }
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

    MonitorMapZones = function(self)
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        for _, v in self.zones do
            local enemies = table.getn(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,v.pos,self.zoneRadius,'Enemy')) > 0
            local allies = table.getn(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,v.pos,self.zoneRadius,'Ally')) > 0
            if enemies and allies then
                v.control = 3
            elseif enemies then
                v.control = 2
            elseif allies then
                v.control = 1
            else
                v.control = 0
            end
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
                if v.control == 3 then
                    DrawCircle(v.pos,5*v.weight,'aa000000')
                elseif v.control == 2 then
                    DrawCircle(v.pos,5*v.weight,'aaff2222')
                elseif v.control == 1 then
                    DrawCircle(v.pos,5*v.weight,'aa22ff22')
                else
                    DrawCircle(v.pos,5*v.weight,'aaffffff')
                end
            end
            WaitTicks(2)
        end
    end,

    Run = function(self)
        self:ForkThread(self.MapMonitoringThread)
        --self:ForkThread(self.MapDrawingThread)
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
