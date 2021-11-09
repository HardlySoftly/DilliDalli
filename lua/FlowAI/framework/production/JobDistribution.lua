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
            numJobExecutors = 0,
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
        self.facotryJobs = {}
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

    JobPrioritisationThread = function(self)
        -- Sort jobs based on priorities and so forth
        -- TODO
    end,

    DistributionThread = function(self)
        -- Distributes idle workers to jobs
        -- TODO
    end,

    ExecutorMonitoringThread = function(self)
        -- Close out completed jobs and attempt to reassign workers.  Add to idle queue if no jobs found.
        -- TODO
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