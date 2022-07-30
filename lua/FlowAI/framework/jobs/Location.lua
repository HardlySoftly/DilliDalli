local WORK_RATE = 10
local GetMarkers = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').GetMarkers
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter
local CreatePriorityQueue = import('/mods/DilliDalli/lua/FlowAI/framework/utils/PriorityQueue.lua').CreatePriorityQueue

local SEARCH_GRID = nil
local SEARCH_GRID_SIZE = -1
local function InitSearchGrid()
    SEARCH_GRID_SIZE = 0
    local remaining = 2500
    local lim = 2*math.sqrt(remaining)
    local pq = CreatePriorityQueue()
    local x = 0
    while x < lim do
        local z = 0
        while z < lim do
            local priority = ((x*x) + (z*z)) * (1 + math.mod(x,2)) * (1 + math.mod(z,2))
            if (x > 0) and (z > 0) then
                pq:Queue({priority = priority, x = -x, z = -z})
            end
            if x > 0 then
                pq:Queue({priority = priority, x = -x, z = z})
            end
            pq:Queue({priority = priority, x = x, z = z})
            if z > 0 then
                pq:Queue({priority = priority, x = x, z = -z})
            end
            z = z+1
        end
        x = x+1
    end
    while remaining > 0 do
        local item = pq:Dequeue()
        remaining = remaining - 1
        SEARCH_GRID_SIZE = SEARCH_GRID_SIZE + 1
        SEARCH_GRID[SEARCH_GRID_SIZE] = {item.x, item.z}
    end
end

do
    InitSearchGrid()
end

LocationManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.locations = {}
        self.numLocations = 0
        local markers = GetMarkers()
        -- Add marker locations
        for _, v in markers do
            local location = MarkerLocation()
            location:Init(self.brain, v.position, v.type)
            self:AddLocation(location)
        end
        -- Add zone locations
        local i = 1
        while i <= self.brain.zoneSet.numZones do
            local zone = self.brain.zoneSet.zones[i]
            local location = ZoneLocation()
            location:Init(self.brain, 1, zone)
            self:AddLocation(location)
            i = i+1
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
            local i = 1
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
    GetBuildPosition = function(self, engineer, blueprintID) end, -- {x, y, z}
    GetCentrePosition = function(self) end, -- {x, y, z}
    StartBuild = function(self, executor, position) end,
    IsFree = function(self) end, -- Boolean
    CheckState = function(self) end,
    BackOff = function(self) end,
})

MarkerLocation = Class(AbstractLocation){
    Init = function(self, brain, centre, markerType)
        self.brain = brain
        self.type = markerType
        self.centre = centre -- {x, y, z}
        self.singular = true
        self.allyOccupied = false
        self.claimed = false
        self.executor = nil
        self.safety = 600
    end,

    GetBuildPosition = function(self, engineer, blueprintID)
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
        local alliedUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.WALL,self.centre,0.2,'Ally')
        self.allyOccupied = alliedUnits and alliedUnits[1]
    end,

    CheckSafety = function(self)
        -- TODO
    end,
}

ZoneLocation = Class(AbstractLocation){
    Init = function(self, brain, component, zone)
        self.brain = brain
        self.component = component
        self.zone = zone
        self.type = "Zone-"..tostring(component)
        self.singular = false
        self.safety = 600
        self.backoff = 0
        self.backoffCount = 0
    end,
    BackOff = function(self)
        -- We returned a nil location, so don't allow new jobs for a while.
        self.backoffCount = self.backoffCount + 1
        self.backoff = math.min(self.backoffCount*10,1000)
    end,
    GetBuildPosition = function(self, engineer, blueprintID)
        local i = 1
        while i <= SEARCH_GRID_SIZE do
            local coord = SEARCH_GRID[i]
            local pos = {self.zone.pos[1]+coord[1], self.zone.pos[2], self.zone.pos[3]+coord[2]}
            if self.brain.aiBrain:CanBuildStructureAt(blueprintID, pos) then
                return pos
            end
            i = i+1
        end
        return nil
    end,
    GetCentrePosition = function(self)
        return self.zone.pos
    end,
    StartBuild = function(self, executor, position)
        -- TODO: build deconfliction
    end,
    IsFree = function(self)
        return self.backoff == 0
    end,
    CheckState = function(self)
        self.backoff = math.max(0, self.backoff - 1)
        self:CheckSafety()
    end,
    CheckSafety = function(self)
        -- TODO
    end,
}