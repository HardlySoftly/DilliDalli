local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}

        self:LoadMapMarkers()
        --self:GetAvailableMarkers()
    end,

    LoadMapMarkers = function(self)
        self.gap = ScenarioInfo.DilliDalliMap.gap
        self.xOffset = ScenarioInfo.DilliDalliMap.xOffset
        self.zOffset = ScenarioInfo.DilliDalliMap.zOffset
        self.xNum = ScenarioInfo.DilliDalliMap.xNum
        self.zNum = ScenarioInfo.DilliDalliMap.zNum
        self.markers = ScenarioInfo.DilliDalliMap.markers
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
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        if not units then
            return true
        end
        for _, v in units do
            local id = v:GetUnitId()
            if IsAlly(myIndex,v:GetArmy()) and EntityCategoryContains(categories.MASSEXTRACTION,v) then
                return false
            end
            local blip = v:GetBlip(myIndex)
            if blip and (blip:IsOnRadar(myIndex) or blip:IsSeenEver(myIndex)) then
                return false
            end
        end
        return true
    end,

    GetEnemyStructure = function(self,pos)
        local units = GetUnitsInRect(Rect(pos[1],pos[3],pos[1],pos[3]))
        if not units or IsAlly(units[1]:GetArmy(),self.brain.aiBrain:GetArmyIndex()) then
            return nil
        else
            return units[1]
        end
    end,

    CanPathToSurface = function(self,pos0,pos1)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]].surf.component == self.markers[indices1[1]][indices1[2]].surf.component
    end,

    MapMonitoringThread = function(self)
        while brain:IsAlive() do
            WaitTicks(10)
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
