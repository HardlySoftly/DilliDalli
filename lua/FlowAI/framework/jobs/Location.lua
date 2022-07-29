local WORK_RATE = 10
local MAP = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').GetMap()
local MARKERS = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').GetMarkers()

LocationManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.locations = {}
        self.numLocations = 0
        -- Add marker locations
        for _, v in MARKERS do
            local location = MarkerLocation()
            location:Init(self.brain, v.position, v.type)
            self:AddLocation(location)
        end
    end,

    AddLocation = function(self, location)
        self.numLocations = self.numLocations + 1
        self.locations[self.numLocations] = location
    end,

    GetLocation = function(self, centre, radius, locationType)
        local i = 1
        local radiusSquare = radius*radius
        while i <= self.numLocations do
            local location = self.locations[i]
            if (location.type == locationType) then
                local xDelta = location.centre[1] - centre[1]
                local zDelta = location.centre[3] - centre[3]
                if xDelta*xDelta + zDelta*zDelta <= radiusSquare then
                    return location
                end
            end
            i = i+1
        end
        return nil
    end,

    GetLocations = function(self, locationType)
        local result = {}
        local i = 1
        while i <= self.numLocations do
            if self.locations[i].type == locationType then
                table.insert(result,self.locations[i])
            end
            i = i+1
        end
        return result
    end,

    LocationMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"LocationManager:LocationMonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            local i = 0
            while i <= self.numLocations do
                local location = self.locations[i]
                location:CheckState()
                workLimiter:MaybeWait()
                i = i+1
            end
        end
        workLimiter:End()
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.LocationMonitoringThread)
    end,
})


AbstractLocation = Class({
    GetBuildPosition = function(self) end, -- {x, y, z}
    GetCentrePosition = function(self) end, -- {x, y, z}
    StartBuild = function(self, executor, position) end,
    IsFree = function(self) end, -- Boolean
    CheckState = function(self) end,
})

MarkerLocation = Class(AbstractLocation){
    Init = function(self, brain, centre, markerType)
        self.brain = brain
        self.type = markerType
        self.centre = centre -- {x, y, z}
        self.singular = true
        self.allyOccupied = false
        self.claimed = false
        self.workItem = nil
        self.safety = 600
    end,

    GetBuildPosition = function(self)
        return {self.centre[1], self.centre[2], self.centre[3]}
    end,

    GetCentrePosition = function(self)
        return {self.centre[1], self.centre[2], self.centre[3]}
    end,

    StartBuild = function(self, executor, position)
        self.claimed = true
        self.executor = executor
    end,

    IsFree = function(self)
        return not (self.allyOccupied or self.claimed)
    end,

    CheckState = function(self)
        self:CheckClaim()
        self:CheckOccupied()
        self:CheckSafety()
    end,

    CheckClaim = function(self)
        if self.claimed then
            self.claimed = not ((self.executor == nil) or self.executor.complete)
            if not self.claimed then
                self.executor = nil
            end
        end
    end,

    CheckOccupied = function(self)
        local alliedUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,pos,0.2,'Ally')
        self.allyOccupied = (not alliedUnits) or (not alliedUnits[1])
    end,

    CheckSafety = function(self)
        -- TODO
    end,
}