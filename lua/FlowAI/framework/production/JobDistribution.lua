--[[
    Distribution of jobs to engies based on priorities and location of units
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

Job = Class({
    Init = function(self, specification)
        -- 'Specification' for the job, describing exactly what kind of thing should be executed
        self.specification = {
            -- Target amount of mass to spend (rate)
            targetSpend = 0,
            -- Target number of things to build
            count = 0,
            -- Max job duplication
            duplicates = 0,
            -- Requirements for the component to build in
            componentRequirement = nil,
            -- Marker type, nil if no marker required
            markerType = nil,
            -- Blueprint ID of the thing to build
            unitBlueprintID = nil,
            -- Blueprint ID of the builder (nil if no restrictions required)
            builderBlueprintID = nil,
            -- Assist flag
            assist = true,
            -- Max ratio of assisters to builders, -1 => no cap.
            assistRatio = -1,
            -- Location to build at (nil if no location requirements)
            location = nil,
            -- Whether to delete this job or not
            self.keep = true
            -- Swap to count based priority.  Useful for things like mass extractor jobs
            self.prioritySwitch = 0
        }
        -- Now that we've initialised with some default values, replace with provided values if they exist
        if specification then
            for k, v in specification do
                self.specification[k] = v
            end
        end

        local bp = GetUnitBlueprintByName(self.specification['unitBlueprintID'])

        -- Job state, maintained between the JobDistribution and JobExecution classes.  Can be read-only accessed otherwise for feedback reasons.
        self.data = {
            -- List of job executors
            executors = {},
            numExecutors = 0,
            -- Spend rate, useful for guessing at buildpower requirements.
            massSpendRate = bp.Economy.BuildCostMass/bp.Economy.BuildTime,
            -- Theoretical spend (assigned builpower * mass rate)
            theoreticalSpend = 0,
            -- Actual spend as measured
            actualSpend = 0,
            -- Stats for measuring the assist ratio effectively
            totalBuildpower = 0,
            assistBuildpower = 0,
            -- Spend ratio (cached version of actualSpend/theoreticalSpend, used for estimating loss of spend when a job completes)
            spendRatio = 1,
            -- Job category
            category = nil
        }
    end,
})

JobDistributor = Class({
    Init = function(self, brain)
        self.brain = brain

        -- Mobile jobs
        self.mobileJobs = {}
        self.numMobileJobs = 0

        -- Factory jobs
        self.factoryJobs = {}
        self.numFactoryJobs = 0

        -- Upgrade jobs
        self.upgradeJobs = {}
        self.numUpgradeJobs = 0
    end,

    AddMobileJob = function(self, job)
        self.numMobileJobs = self.numMobileJobs + 1
        self.mobileJobs[self.numMobileJobs] = job
        job.data.category = "mobile"
    end,

    AddFactoryJob = function(self, job)
        self.numFactoryJobs = self.numFactoryJobs + 1
        self.factoryJobs[self.numFactoryJobs] = job
        job.data.category = "factory"
    end,

    AddUpgradeJob = function(self, job)
        self.numUpgradeJobs = self.numUpgradeJobs + 1
        self.upgradeJobs[self.numUpgradeJobs] = job
        job.data.category = "upgrade"
    end,

    JobDistribution = function(self)
        -- Distributes idle workers to jobs
        -- TODO
    end,

    ExecutorMonitoring = function(self)
        local start = PROFILER:Now()
        -- Close out completed jobs and attempt to reassign workers.
        for _, jobTypeDict in { {self.mobileJobs, false}, {self.factoryJobs, true}, {self.upgradeJobs, true} } do
            local jobs = jobTypeDict[1]
            local isStructureJob = jobTypeDict[2]
            for _, job in jobs do
                local i = 1
                while i <= job.data.numExecutors do
                    local executor = job.data.executors[i]
                    if executor.complete then
                        -- Update job data state
                        executor:UpdateJobState(job)
                        -- Reassign engies
                        if (not isStructureJob) and executor.mainEngie and (not executor.mainEngie.Dead) then
                            self:FindMobileJob(executor.mainEngie)
                        elseif isStructureJob then
                            -- TODO: support fac and upgrade jobs
                        end
                        for _, engie in executor.subsidiaryEngies do
                            if engie and (not engie.Dead) then
                                self:FindMobileJob(engie)
                            end
                        end
                        -- Clear out the executor
                        if i < job.data.numExecutors then
                            job.data.executors[i] = job.data.executors[job.data.numExecutors]
                        end
                        job.data.executors[job.data.numExecutors] = nil
                        job.data.numExecutors = job.data.numExecutors - 1
                    else
                        i = i+1
                    end
                end
            end
        end
        PROFILER:Add("JobDistributor:ExecutorMonitoring",PROFILER:Now()-start)
    end,

    JobMonitoring = function(self)
        -- Kill any dead job references.  May leave executors orphaned, but oh well.
        local start = PROFILER:Now()
        local i = 1
        while i <= self.numMobileJobs do
            if not self.mobileJobs[i].specification.keep then
                if i < self.numMobileJobs then
                    self.mobileJobs[i] = self.mobileJobs[self.numMobileJobs]
                else
                    self.mobileJobs[i] = nil
                end
                self.numMobileJobs = self.numMobileJobs - 1
            else
                i = i + 1
            end
        end
        i = 1
        while i <= self.numFactoryJobs do
            if not self.factoryJobs[i].specification.keep then
                if i < self.numFactoryJobs then
                    self.factoryJobs[i] = self.factoryJobs[self.numFactoryJobs]
                else
                    self.factoryJobs[i] = nil
                end
                self.numFactoryJobs = self.numFactoryJobs - 1
            else
                i = i + 1
            end
        end
        i = 1
        while i <= self.numUpgradeJobs do
            if not self.upgradeJobs[i].specification.keep then
                if i < self.numUpgradeJobs then
                    self.upgradeJobs[i] = self.upgradeJobs[self.numUpgradeJobs]
                else
                    self.upgradeJobs[i] = nil
                end
                self.numUpgradeJobs = self.numUpgradeJobs - 1
            else
                i = i + 1
            end
        end
        PROFILER:Add("JobDistributor:JobMonitoring",PROFILER:Now()-start)
    end,

    FindMobileJob = function(self,engie)
        -- Precondition: engie is not dead!
        local start = PROFILER:Now()
        local bestJob = nil
        local bestExecutor = nil
        local bestPriority = 0
        for _, job in self.mobileJobs do
            local priority = self:StartExecutorPriority(job,engie)
            if priority > bestPriority then
                bestJob = job
                bestExecutor = nil
                bestPriority = priority
            end
            for _, executor in job.data.executors do
                local priority = self:AssistExecutorPriority(job,executor,engie)
                if priority > bestPriority then
                    bestJob = job
                    bestExecutor = executor
                    bestPriority = priority
                end
            end
        end
        for _, job in self.factoryJobs do
            for _, executor in job.data.executors do
                local priority = self:AssistExecutorPriority(job,executor,engie)
                if priority > bestPriority then
                    bestJob = job
                    bestExecutor = executor
                    bestPriority = priority
                end
            end
        end
        for _, job in self.upgradeJobs do
            for _, executor in job.data.executors do
                local priority = self:AssistExecutorPriority(job,executor,engie)
                if priority > bestPriority then
                    bestJob = job
                    bestExecutor = executor
                    bestPriority = priority
                end
            end
        end
        if bestPriority > 0 then
            if bestExecutor then
                self:AssistExecutor(bestJob,bestExecutor,engie)
            else
                self:StartMobileExecutor(bestJob,engie)
            end
        end
        PROFILER:Add("JobDistributor:FindMobileJob",PROFILER:Now()-start)
    end,

    FindStructureJob = function(self,structure)
        -- TODO: Check deadness
        local start = PROFILER:Now()
        local bestJob = nil
        local bestPriority = 0
        local upgradeJob = false
        for _, job in self.factoryJobs do
            local priority = self:StartExecutorPriority(job,engie)
            if priority > bestPriority then
                bestJob = job
                bestPriority = priority
            end
        end
        for _, job in self.upgradeJobs do
            local priority = self:StartExecutorPriority(job,engie)
            if priority > bestPriority then
                bestJob = job
                bestPriority = priority
                upgradeJob = true
            end
        end
        if bestPriority > 0 then
            if upgradeJob then
                self:StartUpgradeExecutor(bestJob,structure)
            else
                self:StartFactoryExecutor(bestJob,structure)
            end
        end
        PROFILER:Add("JobDistributor:FindStructureJob",PROFILER:Now()-start)
    end,

    StartMobileExecutorPriority = function(self,job,engie)
        -- Return the priority for starting an executor for 'job' with 'engie'.
        -- TODO: Swap to better estimates using actual and theoretical mass spends
        -- TODO: Check if it can actually build the thing.  Return -1 if not.
        if job.specification.prioritySwitch then
            return 1 - (job.data.numExecutors+1)/math.min(job.specification.count,job.specification.duplicates)
        else
            local bp = engie:GetBlueprint()
            return 1 - ((job.data.totalBuildpower+bp.Economy.BuildRate)*job.data.massSpendRate)/job.specification.targetSpend
        end
    end,

    StartStructureExecutorPriority = function(self,job,builder)
        -- Return the priority for starting an executor for 'job' with 'builder'.
        -- TODO
        return -1
    end,

    AssistExecutorPriority = function(self,job,executor,engie)
        -- Return the priority for assisting 'executor' with 'engie' (under the given job).
        -- TODO
        return -1
    end,

    StartMobileExecutor = function(self,job,engie)
        -- Given an engineer and a job to start, create an executor (and maintain associated state).
        -- TODO
        local bp = engie:GetBlueprint()
        job.data.totalBuildpower = job.data.totalBuildpower + bp.Economy.BuildRate
        return -1
    end,

    StartFactoryExecutor = function(self,job,factory)
        -- Given an factory and a job to start, create an executor (and maintain associated state).
        -- TODO
        return -1
    end,

    StartUpgradeExecutor = function(self,job,structure)
        -- Given a structure and a job to start, create an executor (and maintain associated state).
        -- TODO
        return -1
    end,

    AssistExecutor = function(self,job,executor,engie)
        -- Get an engie to assist an existing executor
        -- TODO
        return -1
    end,

    ControlThread = function(self)
        -- Global coordinator of stuff.
        local i = 0
        while self.brain:IsAlive() do
            self:ExecutorMonitoring()
            self:JobMonitoring()
            if i%20 == 0 then
                -- Every X ticks reassign idle stuff to jobs where possible
                self:JobDistribution()
            end
            WaitTicks(1)
        end
    end,

    Run = function(self)
        self:ForkThread(self.ControlThread)
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.brain.trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})