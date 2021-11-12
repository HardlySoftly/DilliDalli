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
            -- Manually assigned priority in the range [0,1], useful for things like mass extractor jobs
            self.priority = 0
        }
        -- Now that we've initialised with some default values, replace with provided values if they exist
        if specification then
            for k, v in specification do
                self.specification[k] = v
            end
        end

        -- Internally maintained state, but can be accessed by others for feedback
        self.data = {
            -- List of job executors
            executors = {},
            numExecutors = 0,
            -- Theoretical spend (assigned builpower * mass rate)
            theoreticalSpend = 0,
            -- Actual spend as measured
            actualSpend = 0,
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

    JobPrioritisation = function(self)
        -- Sort jobs based on priorities and so forth
        -- TODO
    end,

    JobDistribution = function(self)
        -- Distributes idle workers to jobs
        -- TODO
    end,

    ExecutorMonitoring = function(self)
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
                        if executor.success then
                            job.specification.count = job.specification.count - 1
                        else
                            WARN('Job failed for reason: '..tostring(executor.reason))
                        end
                        -- TODO: update spend stats here
                        -- Reassign engies
                        if (not isStructureJob) and executor.mainEngie then
                            self:FindMobileJob(executor.mainEngie)
                        elseif isStructureJob then
                            -- TODO: support fac and upgrade jobs
                        end
                        for _, engie in executor.subsidiaryEngies do
                            self:FindMobileJob(engie)
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
    end,

    FindMobileJob = function(self,engie)
    end,

    FindStructureJob = function(self)
    end,

    ControlThread = function(self)
        -- Global coordinator of stuff.
        local i = 0
        while self.brain:IsAlive() do
            self:ExecutorMonitoring()
            if i%20 == 0 then
                self:JobPrioritisation()
                self:JobDistribution()
            end
            WaitTicks(1)
        end
    end,

    Run = function(self)
        self:ForkThread(self.JobPrioritisationThread)
        self:ForkThread(self.DistributionThread)
        self:ForkThread(self.ExecutorMonitoringThread)
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