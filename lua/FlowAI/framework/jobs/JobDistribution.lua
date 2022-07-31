--[[
    In this file, we implement the job distribution layer - responsible for the allocation of builders to jobs.
    We also include helper classes to manage the associated state that gets attached to builders.
]]

local CreateUnitList = import('/mods/DilliDalli/lua/FlowAI/framework/Monitoring.lua').CreateUnitList
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter
local GetProductionGraph = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').GetProductionGraph
local PRIORITY = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Job.lua').PRIORITY

local WORK_RATE = 10

local BuilderData = Class({
    -- Handles builder associated job state
    Init = function(self, builder)
        self.builder = builder

        self.assistingExecutor = false
        self.jobExecutor = nil
        -- Used by executor
        self.previousBuilt = nil
    end,

    SetExecutor = function(self, executor, isAssist)
        self.jobExecutor = executor
        self.assistingExecutor = isAssist
    end,
    IsBusy = function(self)
        if self.jobExecutor.complete then
            self.jobExecutor = nil
        end
        return (self.jobExecutor ~= nil) or (not self.builder.isFinishedUnit)
    end,
    GetLastPosition = function(self)
        -- Return expected position of builder at end of job queue
        return self.builder:GetPosition()
    end,
})
local EngineerData = Class(BuilderData){
    GetLastPosition = function(self)
        -- Return expected position of builder at end of job queue (TODO: Engineers move...)
        return self.builder:GetPosition()
    end,
}


JobDistributor = Class({
    Init = function(self, brain)
        self.brain = brain
        -- Job data
        self.mobileJobs = {}
        self.numMobileJobs = 0
        self.factoryJobs = {}
        self.numFactoryJobs = 0
        self.upgradeJobs = {}
        self.numUpgradeJobs = 0
        -- Builder data
        self.engineers = {}
        self.numEngineers = 0
        self.structures = {}
        self.numStructures = 0
        -- Register interest in mobile things that build other things
        self.newEngineerList = CreateUnitList()
        self.newStructureList = CreateUnitList()
        local pg = GetProductionGraph()
        for bpID, item in pg do
            if (item.buildsN > 0) and item.mobile then
                self.brain.monitoring:RegisterInterest(bpID, self.newEngineerList)
            elseif item.buildsN > 0 then
                self.brain.monitoring:RegisterInterest(bpID, self.newStructureList)
            end
        end
    end,

    AddJob = function(self, job)
        if job.jobType == "mobile" then
            self.numMobileJobs = self.numMobileJobs + 1
            self.mobileJobs[self.numMobileJobs] = job
        elseif job.jobType == "factory" then
            self.numFactoryJobs = self.numFactoryJobs + 1
            self.factoryJobs[self.numFactoryJobs] = job
        elseif job.jobType == "upgrade" then
            self.numUpgradeJobs = self.numUpgradeJobs + 1
            self.upgradeJobs[self.numUpgradeJobs] = job
        end
    end,

    AddEngineer = function(self, engineer)
        self.numEngineers = self.numEngineers + 1
        self.engineers[self.numEngineers] = engineer
        engineer.FlowAI.jobData = EngineerData()
        engineer.FlowAI.jobData:Init(engineer)
    end,

    AddStructure = function(self, structure)
        self.numStructures = self.numStructures + 1
        self.structures[self.numStructures] = structure
        structure.FlowAI.jobData = BuilderData()
        structure.FlowAI.jobData:Init(structure)
    end,

    JobMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"JobDistributor:JobMonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            local i = 1
            while i <= self.numMobileJobs do
                local job = self.mobileJobs[i]
                if (job == nil) or (not job.keep) then
                    self.mobileJobs[i] = self.mobileJobs[self.numMobileJobs]
                    self.mobileJobs[self.numMobileJobs] = nil
                    self.numMobileJobs = self.numMobileJobs - 1
                else
                    job:CheckState()
                    i = i+1
                end
                workLimiter:MaybeWait()
            end
            i = 1
            while i <= self.numFactoryJobs do
                local job = self.factoryJobs[i]
                if (job == nil) or (not job.keep) then
                    self.factoryJobs[i] = self.factoryJobs[self.numFactoryJobs]
                    self.factoryJobs[self.numFactoryJobs] = nil
                    self.numFactoryJobs = self.numFactoryJobs - 1
                else
                    job:CheckState()
                    i = i+1
                end
                workLimiter:MaybeWait()
            end
            i = 1
            while i <= self.numUpgradeJobs do
                local job = self.upgradeJobs[i]
                if (job == nil) or (not job.keep) then
                    self.upgradeJobs[i] = self.upgradeJobs[self.numUpgradeJobs]
                    self.upgradeJobs[self.numUpgradeJobs] = nil
                    self.numUpgradeJobs = self.numUpgradeJobs - 1
                else
                    job:CheckState()
                    i = i+1
                end
                workLimiter:MaybeWait()
            end
        end
        workLimiter:End()
    end,

    AssignEngineers = function(self, workLimiter)
        -- Check + Assign known engineers
        local i = 1
        while i <= self.numEngineers do
            local engineer = self.engineers[i]
            if (engineer == nil) or engineer.Dead then
                self.engineers[i] = self.engineers[self.numEngineers]
                self.engineers[self.numEngineers] = nil
                self.numEngineers = self.numEngineers - 1
            else
                if not engineer.FlowAI.jobData:IsBusy() then
                    -- Assign job
                    self:EngineerFindJob(engineer)
                    workLimiter:MaybeWait()
                end
                i = i+1
            end
        end
        -- Fetch + Assign new engineers
        local engineer = self.newEngineerList:FetchUnit()
        while engineer do
            self:AddEngineer(engineer)
            if engineer.isFinishedUnit then
                self:EngineerFindJob(engineer)
                workLimiter:MaybeWait()
            end
            engineer = self.newEngineerList:FetchUnit()
        end
    end,

    AssignStructures = function(self, workLimiter)
        -- Check + Assign known structures
        local i = 0
        while i <= self.numStructures do
            local structure = self.structures[i]
            if (structure == nil) or structure.Dead then
                self.structures[i] = self.structures[self.numStructures]
                self.structures[self.numStructures] = nil
                self.numStructures = self.numStructures - 1
            else
                if not structure.FlowAI.jobData:IsBusy() then
                    -- Assign job
                    self:StructureFindJob(structure)
                    workLimiter:MaybeWait()
                end
                i = i+1
            end
        end
        -- Fetch + Assign new structures
        local structure = self.newStructureList:FetchUnit()
        while structure do
            self:AddStructure(structure)
            if structure.isFinishedUnit then
                self:StructureFindJob(structure)
                workLimiter:MaybeWait()
            end
            structure = self.newStructureList:FetchUnit()
        end
    end,

    BuilderMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"JobDistributor:BuilderMonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            self:AssignEngineers(workLimiter)
            self:AssignStructures(workLimiter)
        end
        workLimiter:End()
    end,

    StartJob = function(self, engineer, workItem)
        local executor = workItem:StartJob(engineer, self.brain)
        engineer.FlowAI.jobData:SetExecutor(executor, false)
    end,

    AssistJob = function(self, engineer, workItem)
        local executor = workItem:AssistJob(engineer)
        engineer.FlowAI.jobData:SetExecutor(executor, true)
    end,

    EngineerFindJob = function(self, engineer)
        -- TODO: find best engineer for jobs, as well as best jobs for engineers
        local bestWorkItem = nil
        local assist = false
        local bestPriority = PRIORITY.NONE
        local bestUtility = 0
        local i = 1
        while i <= (self.numMobileJobs+self.numFactoryJobs+self.numUpgradeJobs) do
            local job = nil
            if i <= self.numMobileJobs then
                job = self.mobileJobs[i]
            elseif i <= self.numMobileJobs+self.numFactoryJobs then
                job = self.factoryJobs[i-self.numMobileJobs]
            else
                job = self.upgradeJobs[i-self.numMobileJobs-self.numFactoryJobs]
            end
            -- Job exists, is active, has priority, has budget, is below budget
            if job and job.keep and (job.priority >= bestPriority) and (job.budget > 0) and (job:GetSpend() < job.budget) then
                local candidate = self:FindWorkItemEngineer(engineer, job)
                if (candidate.utility > 0) and ((job.priority > bestPriority) or (candidate.utility > bestUtility)) then
                    bestWorkItem = candidate.workItem
                    bestPriority = job.priority
                    bestUtility = candidate.utility
                    assist = candidate.assist
                end
            end
            i = i+1
        end
        if bestWorkItem and (not assist) then
            self:StartJob(engineer, bestWorkItem)
        elseif bestWorkItem then
            self:AssistJob(engineer, bestWorkItem)
        end
    end,

    StructureFindJob = function(self, structure)
        -- TODO: find best structure for jobs, as well as best jobs for structures
        local bestWorkItem = nil
        local bestPriority = PRIORITY.NONE
        local bestUtility = 0
        local i = 1
        while i <= self.numFactoryJobs+self.numUpgradeJobs do
            local job = nil
            if i <= self.numFactoryJobs then
                job = self.factoryJobs[i]
            else
                job = self.upgradeJobs[i-self.numFactoryJobs]
            end
            -- Job exists, is active, has priority, has budget, is below budget
            if job and job.keep and (job.priority >= bestPriority) and (job.budget > 0) and (job:GetSpend() < job.budget) then
                local candidate = self:FindWorkItemStructure(structure, job)
                if (candidate.utility > 0) and ((job.priority > bestPriority) or (candidate.utility > bestUtility)) then
                    bestWorkItem = candidate.workItem
                    bestPriority = job.priority
                    bestUtility = candidate.utility
                end
            end
            i = i+1
        end
        if bestWorkItem then
            self:StartJob(structure, bestWorkItem)
        end
    end,

    FindWorkItemEngineer = function(self, engineer, job)
        local candidate = { utility = 0, workItem = nil, assist = false }
        local jobCanStart = job:CanStartBuild(engineer)
        local j = 1
        local budgetScalar = (job.budget - job:GetSpend())/job.budget
        while j <= job.numWorkItems do
            local workItem = job.workItems[j]
            if workItem and workItem.keep then
                -- Calculate and cache the ability to start / assist first (this is cheaper than running GetUtility)
                local canAssist = workItem:CanAssistWith(engineer)
                local canStart = jobCanStart and workItem:CanStartWith(engineer)
                if canAssist or canStart then
                    local utility = workItem:GetUtility(engineer)*budgetScalar
                    if utility > candidate.utility then
                        candidate.workItem = workItem
                        candidate.utility = utility
                        candidate.assist = canAssist
                    end
                end
            end
            j = j+1
        end
        return candidate
    end,

    FindWorkItemStructure = function(self, structure, job)
        local candidate = { utility = 0, workItem = nil }
        if not job:CanStartBuild(structure) then
            return candidate
        end
        local j = 1
        local budgetScalar = (job.budget - job:GetSpend())/job.budget
        while j <= job.numWorkItems do
            local workItem = job.workItems[j]
            if workItem and workItem.keep then
                -- Calculate and cache the ability to start / assist first (this is cheaper than running GetUtility)
                if workItem:CanStartWith(structure) then
                    local utility = workItem:GetUtility(structure)*budgetScalar
                    if utility > candidate.utility then
                        candidate.workItem = workItem
                        candidate.utility = utility
                    end
                end
            end
            j = j+1
        end
        return candidate
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.BuilderMonitoringThread)
        self.brain:ForkThread(self, self.JobMonitoringThread)
    end,
})