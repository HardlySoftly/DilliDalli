local WORK_RATE = 10

local Job = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Job.lua')
local Utility = import('/mods/DilliDalli/lua/FlowAI/framework/economy/Utility.lua')
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter

local LARGE_NUMBER = 1000000000

MassMarkerManager = Class({
    Init = function(self, brain)
        self.brain = brain
        self.job = Job.Job()
        self.job:Init("MEX_T1", "mobile", Job.PRIORITY.NORMAL, false)
        self.job:SetCount(LARGE_NUMBER)
        self.marginalEnergyCost = 20/75
        self.workItems = {}
        self.numItems = 0
        local locations = self.brain.locationManager:GetLocations("Mass")
        for _, location in locations do
            local workItem = self.job:AddWorkItem(location)
            self.numItems = self.numItems + 1
            self.workItems[self.numItems] = workItem
        end
        self.brain.jobDistributor:AddJob(self.job)
    end,

    MarkerMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"MassMarkerManager:MarkerMonitoringThread")
        local massProduction = self.job.bp.Economy.ProductionPerSecondMass or 0
        local massCost = self.job.bp.Economy.BuildCostMass or LARGE_NUMBER
        local energyMaintenance = self.job.bp.Economy.MaintenanceConsumptionPerSecondEnergy or LARGE_NUMBER
        while self.brain:IsAlive() and workLimiter:Wait() do
            --[[
                For each WorkItem in self.workItems, do the following:
                    Check if location is available, and set utility to 0 if not.
                    Update utility based on location safety and economic conditions
            ]]
            local i = 1
            while i <= self.numItems do
                local workItem = self.workItems[i]
                if workItem.location:IsFree() then
                    workItem:SetUtility(Utility.GetMassUtility(massProduction, massCost, energyMaintenance, self.marginalEnergyCost, workItem.location.safety))
                    -- TODO: accumulate spend / max spend stats?
                else
                    workItem:SetUtility(0)
                end
                workLimiter:MaybeWait()
                i = i+1
            end
        end
        workLimiter:End()
    end,

    SetMarginalEnergyCost = function(self, marginalEnergyCost) self.marginalEnergyCost = marginalEnergyCost end,
    SetBudget = function(self, budget) self.job:SetBudget(budget) end,
    GetSpend = function(self) return self.job:GetSpend() end,
    GetMaxSpend = function(self)
        -- TODO: Check number of free locations, and update based on that
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.MarkerMonitoringThread)
    end,
})