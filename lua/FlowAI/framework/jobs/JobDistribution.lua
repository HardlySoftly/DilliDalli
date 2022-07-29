--[[
    In this file, we implement the job distribution layer - responsible for the allocation of builders to jobs.
    We also include helper classes to manage the associated state that gets attached to builders.
]]

local CreateUnitList = import('/mods/DilliDalli/lua/FlowAI/framework/Monitoring.lua').CreateUnitList
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter
local GetProductionGraph = import('/mods/DilliDalli/lua/FlowAI/framework/production/ProductionGraph.lua').GetProductionGraph
local PRIORITY = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Job.lua').PRIORITY

local WORK_RATE = 10

local EngineerData = Class({
    -- Handles engineer associated job state
    Init = function(self, engineer)
        self.engineer = engineer

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
        if this.jobExecutor.complete then
            this.jobExecutor = nil
        end
        return this.jobExecutor ~= nil
    end,
    GetLastPosition = function(self)
        -- Return expected position of engineer at end of job queue (TODO)
        return self.engineer:GetPosition()
    end,
})

JobDistributor = Class({
    Init = function(self, brain)
        self.brain = brain
        self.jobs = {}
        self.numJobs = 0
        self.engineers = {}
        self.numEngineers = 0
        -- Register interest in mobile things that build other things
        self.newUnitList = CreateUnitList()
        local pg = GetProductionGraph()
        for bpID, item in pg do
            if (item.buildsN > 0) and item.mobile then
                self.brain.monitoring:RegisterInterest(bpID, self.newUnitList)
            end
        end
    end,

    AddJob = function(self, job)
        self.numJobs = self.numJobs + 1
        self.jobs[numJobs] = job
    end,

    AddEngineer = function(self, engineer)
        self.numEngineers = self.numEngineers + 1
        self.engineers[self.numEngineers] = engineer
        engineer.FlowAI.jobData = EngineerData()
        engineer.FlowAI.jobData:Init(engineer)
    end,

    JobMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"JobDistributor:JobMonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            local i = 0
            while i <= self.numJobs do
                local job = self.jobs[i]
                if (job == nil) or (not job.keep) then
                    self.jobs[i] = self.jobs[self.numJobs]
                    self.jobs[self.numJobs] = nil
                    self.numJobs = self.numJobs - 1
                else
                    job:CheckState()
                    i = i+1
                end
                workLimiter:MaybeWait()
            end
        end
        workLimiter:End()
    end,

    EngineerMonitoringThread = function(self)
        local workLimiter = CreateWorkLimiter(WORK_RATE,"JobDistributor:EngineerMonitoringThread")
        while self.brain:IsAlive() and workLimiter:Wait() do
            local i = 0
            while i <= self.numEngineers do
                local engineer = self.engineers[i]
                if (engineer == nil) or engineer.Dead then
                    self.engineers[i] = self.engineers[self.numEngineers]
                    self.engineers[self.numEngineers] = nil
                    self.numEngineers = self.numEngineers - 1
                else
                    if not engineer.FlowAI.jobData:IsBusy() then
                        -- Assign job
                        self:FindJob(engineer)
                        workLimiter:MaybeWait()
                    end
                    i = i+1
                end
            end
            local engineer = self.newUnitList:FetchUnit()
            while engineer do
                self:AddEngineer(engineer)
                self:FindJob(engineer)
                workLimiter:MaybeWait()
                engineer = self.newUnitList:FetchUnit()
            end
        end
        workLimiter:End()
    end,

    StartJob = function(self, engineer, workItem)
        local executor = workItem:StartJob(engineer)
        engineer.jobData:SetExecutor(executor, false)
    end,

    AssistJob = function(self, engineer, workItem)
        local executor = workItem:AssistJob(engineer)
        engineer.jobData:SetExecutor(executor, true)
    end,

    FindJob = function(self, engineer)
        local bestWorkItem = nil
        local assist = false
        local bestPriority = PRIORITY.NONE
        local bestUtility = 0
        local i = 0
        while i <= self.numJobs do
            local job = self.jobs[i]
            local spend = job:GetSpend()
            if (job == nil) or (not job.keep) then
                self.jobs[i] = self.jobs[self.numJobs]
                self.jobs[self.numJobs] = nil
                self.numJobs = self.numJobs - 1
            else
                if (job.priority >= bestPriority) and (job.budget > 0) and (spend < job.budget) then
                    local j = 0
                    local budgetScalar = (job.budget - spend)/job.budget
                    while j <= job.numWorkItems do
                        local workItem = job.workItems[j]
                        if (not (workItem == nil)) and workItem.keep then
                            local utility = workItem:GetUtility(engineer)*budgetScalar
                            if ((job.priority > bestPriority) or (utility > bestUtility)) then
                                if workItem:CanAssistWith(engineer)
                                    bestWorkItem = workItem
                                    bestPriority = job.priority
                                    bestUtility = utility
                                    assist = true
                                elseif workItem:CanStartWith(engineer) then
                                    bestWorkItem = workItem
                                    bestPriority = job.priority
                                    bestUtility = utility
                                    assist = false
                                end
                            end
                        end
                        j = j+1
                    end
                end
                i = i+1
            end
        end
        if bestWorkItem and (not assist) then
            self:StartJob(engineer, bestWorkItem)
        elseif bestWorkItem then
            self:AssistJob(engineer, bestWorkItem)
        end
    end,
})