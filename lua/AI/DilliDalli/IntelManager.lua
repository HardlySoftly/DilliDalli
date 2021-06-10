local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.centre = {ScenarioInfo.size[1],0,ScenarioInfo.size[2]}

        self:ForkThread(self.LoadMapMarkers)
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
        for _, v in markers do
            if v.type == t then
                local dist = VDist3(pos,v.position)
                if dist < best and self:MarkerNotClaimed(v) then
                    best = dist
                    bestMarker = v
                end
            end
        end
        return bestMarker
    end,

    MarkerNotClaimed = function(self,marker)
        -- TODO: make this intel compliant.
        local units = GetUnitsInRect(marker.position[1],marker.position[3],marker.position[1],marker.position[3])
        if not units then
            return true
        else
            return table.getn(units) == 0
        end
    end,

    CanPathToSurface = function(self,pos0,pos1)
        local indices0 = self:GetIndices(pos0[1],pos0[3])
        local indices1 = self:GetIndices(pos1[1],pos1[3])
        return self.markers[indices0[1]][indices0[2]].surf.component == self.markers[indices1[1]][indices1[2]].surf.component
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
