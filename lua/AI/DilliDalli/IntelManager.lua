local BOs = import('/mods/DilliDalli/lua/AI/DilliDalli/BuildOrders.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

IntelManager = Class({
    Initialise = function(self,brain)
        self.brain = brain
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

