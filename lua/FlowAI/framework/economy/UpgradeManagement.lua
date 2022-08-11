local WORK_RATE = 10

local Job = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Job.lua')
local Utility = import('/mods/DilliDalli/lua/FlowAI/framework/economy/Utility.lua')
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter
local CreateUnitList = import('/mods/DilliDalli/lua/FlowAI/framework/Monitoring.lua').CreateUnitList

local LARGE_NUMBER = 1000000000

MassUpgradeManager = Class({
    Init = function(self, brain, productionID, upgradeID)
        self.brain = brain
        self.job = Job.Job()
        self.job:Init(upgradeID, "upgrade", Job.PRIORITY.NORMAL, false)
        self.job:SetCount(LARGE_NUMBER)
        self.marginalEnergyCost = 20/75
        self.workItems = {}
        self.numItems = 0
        self.unitList = CreateUnitList()
        local bpIDs = Job.GetBlueprintIDs(productionID)
        for _, bpID in bpIDs do
            self.brain.monitoring:RegisterInterest(bpID, self.unitList)
        end
        self.brain.jobDistributor:AddJob(self.job)
    end,

    AddWorkItem = function(self, mex)
        local workItem = self.job:AddWorkItem(mex)
        workItem.custom.location = self.brain.locationManager:GetLocation(mex:GetPosition(), 0.5, "Mass")
        self.numItems = self.numItems + 1
        self.workItems[self.numItems] = workItem
    end,

    MonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"MassUpgradeManager:MonitoringThread")
        local massProduction = self.job.bp.Economy.ProductionPerSecondMass or 0
        local massCost = self.job.bp.Economy.BuildCostMass or LARGE_NUMBER
        local energyMaintenance = self.job.bp.Economy.MaintenanceConsumptionPerSecondEnergy or LARGE_NUMBER
        while self.brain:IsAlive() and workLimiter:Wait() do
            --[[
                For each WorkItem in self.workItems, do the following:
                    Check if mex still exists, tidy up if not.
                    Update utility based on location safety and economic conditions
            ]]
            local i = 1
            while i <= self.numItems do
                local workItem = self.workItems[i]
                if workItem.structure and (not workItem.structure.Dead) then
                    local structureBP = workItem.structure:GetBlueprint()
                    local marginalMassProduction = massProduction - (structureBP.Economy.ProductionPerSecondMass or 0)
                    local marginalEnergyMaintenance = energyMaintenance - (structureBP.Economy.MaintenanceConsumptionPerSecondEnergy or LARGE_NUMBER)
                    workItem:SetUtility(Utility.GetMassUtility(marginalMassProduction, massCost, marginalEnergyMaintenance, self.marginalEnergyCost, workItem.custom.location.safety))
                    -- TODO: accumulate spend / max spend stats?
                    workLimiter:MaybeWait()
                    i = i+1
                else
                    workItem:Destroy()
                    self.workItems[i] = self.workItems[self.numItems]
                    self.workItems[self.numItems] = nil
                    self.numItems = self.numItems - 1
                end
            end
            -- Find new mexes to add as work items
            local mex = self.unitList:FetchUnit()
            while mex do
                self:AddWorkItem(mex)
                mex = self.unitList:FetchUnit()
            end
        end
        workLimiter:End()
    end,

    SetMarginalEnergyCost = function(self, marginalEnergyCost) self.marginalEnergyCost = marginalEnergyCost end,
    SetBudget = function(self, budget) self.job:SetBudget(budget) end,
    GetSpend = function(self) return self.job:GetSpend() end,

    Run = function(self)
        self.brain:ForkThread(self, self.MonitoringThread)
    end,
})