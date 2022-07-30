--[[
    In this file, we implement two principle concepts:
        - The "Job" - a template for production of a single kind of "thing"
        - The WorkItem - a specific instance of a job, bound to a particular unit/location.

    Jobs can have many WorkItems, and WorkItems can only have a single parent job.

    Creators of jobs first create the parent job, then assign individual WorkItems to it.
    These WorkItems can (and will) have distinct "utility" values, e.g. to account for some locations being safer than others.

    WorkItems are responsible for the starting and monitoring of job executors.

    PS: There's poor separation of concerns right now between these classes and the JobDistributor implentation, so bear in mind if you start changing things here."
]]

local MAP = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').GetMap()
local GetProductionGraph = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').GetProductionGraph

local JobExecution = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/JobExecution.lua')

-- Don't add buildpower if the buildtime will drop below this
local MIN_BUILD_TIME_SECONDS = 15
--[[
    Utility modification calculation is as follows:
    base_utility/(1+math.max(0,(time_to_start-BASE_MOVE_TIME_SECONDS)/UTILITY_HALF_RATE_SECONDS))
]]
local BASE_MOVE_TIME_SECONDS = 5
local UTILITY_HALF_RATE_SECONDS = 15


local PRODUCTION_GRAPH = nil


PRIORITY = {
    NONE = 0,
    LOW = 100,
    NORMAL = 200,
    HIGH = 300,
    CRITICAL = 400
}

local PRODUCTION_TRANSLATION = {
    MEX_T1 = { "uab1103", "ueb1103", "urb1103", "xsb1103" },
    MEX_T2 = { "uab1202", "ueb1202", "urb1202", "xsb1202" },
    MEX_T2 = { "uab1302", "ueb1302", "urb1302", "xsb1302" },
    POWER_T1 = { "uab1101", "ueb1101", "urb1101", "xsb1101" },
    POWER_T2 = { "uab1201", "ueb1201", "urb1201", "xsb1201" },
    POWER_T3 = { "uab1301", "ueb1301", "urb1301", "xsb1301" }
}

local function CanBuild(builder, productionID)
    if PRODUCTION_TRANSLATION[productionID] then
        for k, bpID in PRODUCTION_TRANSLATION[productionID] do
            if builder:CanBuild(bpID) then
                return true
            end
        end
        return false
    else
        return builder:CanBuild(productionID)
    end
end

local function TranslateProductionID(builder, productionID)
    if PRODUCTION_TRANSLATION[productionID] then
        for k, bpID in PRODUCTION_TRANSLATION[productionID] do
            if builder:CanBuild(bpID) then
                return bpID
            end
        end
        return false
    else
        return productionID
    end
end

WorkItem = Class({
    Init = function(self, job)
        self.job = job
        self.utility = 0
        self.keep = true
        self.executors = {}
        self.numExecutors = 0
        self.maxBuildpower = self.job.buildTime/MIN_BUILD_TIME_SECONDS
    end,
    -- Job owner interface functions
    Destroy = function(self) self.keep = false end,
    SetUtility = function(self, utility) self.utility = utility end,
})

MobileWorkItem = Class(WorkItem){
    Init = function(self, job, location)
        WorkItem.Init(self, job)
        self.location = location
    end,

    -- Job distributor interface
    CanStartWith = function(self, engineer)
        -- Are we already maxed on this job?
        if self.job.active >= self.job.count then
            return false
        end
        -- Check if the location is free
        if not self.location:IsFree() then
            return false
        end
        -- Is the job pathable?
        if not MAP:UnitCanPathTo(engineer, self.location:GetCentrePosition()) then
            return false
        end
        -- Can this engineer even produce this job?
        if not CanBuild(engineer, self.job.productionID) then
            return false
        end
        return true
    end,
    CanAssistWith = function(self, engineer)
        local i = 1
        while i <= self.numExecutors do
            local executor = self.executors[i]
            if (not executor.complete) and (executor:GetBuildpower() < self.maxBuildpower) and MAP:UnitCanPathTo(engineer, executor.buildLocation) then
                return true
            end
            i = i+1
        end
        return false
    end,
    StartJob = function(self, engineer, brain)
        -- Create executor
        local bpID = TranslateProductionID(engineer, self.job.productionID)
        local buildLocation = self.location:GetBuildPosition(engineer, bpID)
        if buildLocation == nil then
            self.location:BackOff()
            return nil
        end
        local executor = JobExecution.MobileJobExecutor()
        executor:Init(brain, engineer, bpID, buildLocation)
        executor:Run()
        -- Store executor
        self.numExecutors = self.numExecutors + 1
        self.executors[self.numExecutors] = executor
        -- Update job state
        self.job.active = self.job.active + 1
        local bp = engineer:GetBlueprint()
        self.job.buildpower = self.job.buildpower + bp.Economy.BuildRate
        self.location:StartBuild(executor, buildLocation)
        -- Finish
        return executor
    end,
    AssistJob = function(self, engineer)
        -- Precondition: you must have first called self:CanAssistWith(engineer)
        local executor = self.executors[1]
        local lowestBuildpower = executor:GetBuildpower()
        local i = 2
        while i <= self.numExecutors do
            local buildpower = self.executors[i]:GetBuildpower()
            if buildpower < lowestBuildpower then
                executor = self.executors[i]
                lowestBuildpower = buildpower
            end
        end
        executor:AddEngineer(engineer)
        local bp = engineer:GetBlueprint()
        self.job.buildpower = self.job.buildpower + bp.Economy.BuildRate
        return executor
    end,
    GetUtility = function(self, engineer)
        -- Return modified own utility
        if self.utility <= 0 then
            return 0
        end
        -- TODO: Account for risk to engineer
        local bp = engineer:GetBlueprint()
        local maxSpeed = bp.Physics.MaxSpeed
        if bp.Physics.MotionType == "RULEUMT_Air" then
            maxSpeed = bp.Air.MaxAirspeed
        end
        if maxSpeed <= 0 then
            maxSpeed = 0.1
        end
        local pos = engineer.FlowAI.jobData:GetLastPosition()
        local destination = self.location:GetCentrePosition()
        local xDelta = destination[1] - pos[1]
        local zDelta = destination[3] - pos[3]
        local distance = math.sqrt(xDelta*xDelta + zDelta*zDelta)
        local timeToStart = distance/maxSpeed
        return (
            self.utility /
            (1 + math.max(0,(timeToStart-BASE_MOVE_TIME_SECONDS)/UTILITY_HALF_RATE_SECONDS))
        )
    end,
    GetBuildpower = function(self)
        -- Return a normalised buildpower rate for this work item
        local buildpower = 0
        local i = 1
        while i <= self.numExecutors do
            buildpower = buildpower + self.executors[i]:GetBuildpower()
            i = i+1
        end
        return buildpower
    end,
    CheckState = function(self)
        local i = 1
        while i <= self.numExecutors do
            if self.executors[i].complete then
                if self.executors[i].success then
                    self.job.count = self.job.count - 1
                end
                self.executors[i]:CompleteJob()
                self.executors[i] = self.executors[self.numExecutors]
                self.executors[self.numExecutors] = nil
                self.numExecutors = self.numExecutors - 1
                self.job.active = self.job.active - 1
            else
                i = i+1
            end
        end
    end,
    IsActive = function(self)
        return self.keep or (self.numExecutors > 0)
    end,
}

Job = Class({
    Init = function(self, productionID, jobType, priority, debugJob)
        if PRODUCTION_GRAPH == nil then
            PRODUCTION_GRAPH = GetProductionGraph()
        end
        -- Keep the job, or drop?
        self.keep = true
        -- Debugging flag
        self.debugJob = debugJob
        self.lastDebug = 0
        -- Specification data, simple values
        self.productionID = productionID
        self.priority = priority
        self.jobType = jobType
        -- Internal, set via helper methods
        self.count = 0
        self.budget = 0
        -- Internal state
        self.active = 0
        self.buildpower = 0
        self.workItems = {}
        self.numWorkItems = 0

        -- TODO: Handle translation layer better
        self.bp = nil
        if PRODUCTION_TRANSLATION[self.productionID] then
            self.bp = GetUnitBlueprintByName(PRODUCTION_TRANSLATION[self.productionID][1])
        else
            self.bp = GetUnitBlueprintByName(self.productionID)
        end
        self.buildTime = self.bp.Economy.BuildTime
        self.buildRate = self.bp.Economy.BuildCostMass/self.buildTime
    end,

    AddWorkItem = function(self, item)
        local workItem = nil
        if self.jobType == "mobile" then
            workItem = MobileWorkItem()
        elseif self.jobType == "factory" then
            --TODO: workItem = FactoryWorkItem()
        else
            --TODO: workItem = UpgradeWorkItem()
        end
        workItem:Init(self, item)
        self.numWorkItems = self.numWorkItems + 1
        self.workItems[self.numWorkItems] = workItem
        return workItem
    end,

    SetPriority = function(self, priority) self.priority = priority end,
    SetBudget = function(self, budget) self.budget = budget end,
    SetCount = function(self, count) self.count = count end,
    GetSpend = function(self) return self.buildpower*self.buildRate end,
    Destroy = function(self) self.keep = false end,

    CheckState = function(self)
        self.buildpower = 0
        local i = 1
        while i <= self.numWorkItems do
            local workItem = self.workItems[i]
            workItem:CheckState()
            if not workItem:IsActive() then
                self.workItems[i] = self.workItems[self.numWorkItems]
                self.workItems[self.numWorkItems] = nil
                self.numWorkItems = self.numWorkItems - 1
            else
                self.buildpower = self.buildpower + workItem:GetBuildpower()
                i = i+1
            end
        end
        if self.debugJob and (_G.GetGameTick() >= self.lastDebug+20) then
            self.lastDebug = _G.GetGameTick()
            _ALERT((
                "Job Debug: {pri: "..tostring(self.priority)..
                ", budget: "..tostring(self.budget)..
                ", buildpower: "..tostring(self.buildpower)..
                ", numWorkItems: "..tostring(self.numWorkItems)..
                ", count: "..tostring(self.count)..
                ", active: "..tostring(self.active)..
                "}"
            ))
        end
    end,
})