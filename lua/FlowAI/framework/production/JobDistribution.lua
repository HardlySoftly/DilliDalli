--[[
    Distribution of jobs to engies based on priorities and location of units
    TODOs:
        Add support for assistance
        Respect component location requirements
        Add support for marker based mobile jobs (mexes / hydros)
        Handle failures to find locations better
        Flag engies / jobs that are failing repeatedly and try to fix them
        Exchange jobs where sensible
        Prioritise jobs/assistance based on proximity
        Dynamically lower assigned resources to jobs
        Focus assistance for mobile jobs, spread it for factory jobs
        Add diagnosis tooling
        Eliminate for loops - they may not work.
        More profiling
        Respect assistance ratios
        Improve prioritisation as regards assistance, e.g. dynamic picking of suitable assistance ratios
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

local MobileJobExecutor = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobExecution.lua').MobileJobExecutor
local FactoryJobExecutor = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobExecution.lua').FactoryJobExecutor
local UpgradeJobExecutor = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobExecution.lua').UpgradeJobExecutor

-- Use this so that priority 0 jobs can still be started (e.g. hitting count/spend limit)
local SMALL_NEGATIVE = -0.0000001

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
            -- Location to build at (nil if no specific location requirements)
            location = nil,
            -- Safety requirements for building (nil if no specific requirement)
            safety = nil,
            -- Whether to delete this job or not
            keep = true,
            -- Swap to count based priority.  Useful for things like mass extractor jobs
            prioritySwitch = false,
        }
        -- Now that we've initialised with some default values, replace with provided values if they exist
        if specification then
            for k, v in specification do
                self.specification[k] = v
            end
        end

        local bp = GetUnitBlueprintByName(self.specification.unitBlueprintID)

        -- Job state, maintained between the JobDistribution and JobExecution classes.  Can be read-only accessed otherwise for feedback reasons.
        self.data = {
            -- List of job executors
            executors = {},
            numExecutors = 0,
            -- Spend rate, useful for guessing at buildpower requirements.
            massSpendRate = bp.Economy.BuildCostMass/bp.Economy.BuildTime,
            -- Ratio of energy spend to mass spend, useful for working out overall energy requirements.
            energyRatio = bp.Economy.BuildCostMass/bp.Economy.BuildCostEnergy,
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
    Init = function(self, brain, map)
        self.brain = brain
        self.map = map

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
        -- TODO: Improve this
        local units = self.brain.aiBrain:GetListOfUnits(categories.MOBILE*categories.ENGINEER,false,true)
        for _, v in units do
            if not v.FlowAI then
                v.FlowAI = {}
            end
            if not v.FlowAI.ProductionAssigned then
                self:FindMobileJob(v)
            end
        end
        local units = self.brain.aiBrain:GetListOfUnits(categories.FACTORY,false,true)
        for _, v in units do
            if not v.FlowAI then
                v.FlowAI = {}
            end
            if not v.FlowAI.ProductionAssigned then
                self:FindStructureJob(v)
            end
        end
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
                        -- Clear out the executor
                        if i < job.data.numExecutors then
                            job.data.executors[i] = job.data.executors[job.data.numExecutors]
                        end
                        job.data.executors[job.data.numExecutors] = nil
                        job.data.numExecutors = job.data.numExecutors - 1
                        -- Update job data state
                        executor:CompleteJob(job)
                        if not isStructureJob then
                            if job.specification.markerType then
                                self.brain.markerManager:ClearMarker(executor.buildID)
                            else
                                self.brain.deconfliction:Clear(executor.buildID)
                            end
                        end
                        -- Reassign builders
                        if (not isStructureJob) and executor.mainBuilder and (not executor.mainBuilder.Dead) then
                            executor.mainBuilder.FlowAI.ProductionAssigned = false
                            self:FindMobileJob(executor.mainBuilder)
                        elseif isStructureJob and executor.mainBuilder and (not executor.mainBuilder.Dead) then
                            self:FindStructureJob(executor.mainBuilder)
                        end
                        local j = 1
                        while j < executor.numEngies do
                            local engie = executor.subsidiaryEngies[j]
                            if engie and (not engie.Dead) then
                                engie.FlowAI.ProductionAssigned = false
                                self:FindMobileJob(engie)
                            end
                            j = j+1
                        end
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
        -- Precondition: engie is not dead, and also not assigned.
        local start = PROFILER:Now()
        local bestJob = nil
        local bestExecutor = nil
        local bestPriority = SMALL_NEGATIVE
        for _, job in self.mobileJobs do
            local priority = self:StartExecutorPriority(job,engie)
            if priority > bestPriority then
                bestJob = job
                bestExecutor = nil
                bestPriority = priority
            end
            for _, executor in job.data.executors do
                local priority = self:StartAssistExecutorPriority(job,executor,engie)
                if priority > bestPriority then
                    bestJob = job
                    bestExecutor = executor
                    bestPriority = priority
                end
            end
        end
        for _, job in self.factoryJobs do
            for _, executor in job.data.executors do
                local priority = self:StartAssistExecutorPriority(job,executor,engie)
                if priority > bestPriority then
                    bestJob = job
                    bestExecutor = executor
                    bestPriority = priority
                end
            end
        end
        for _, job in self.upgradeJobs do
            for _, executor in job.data.executors do
                local priority = self:StartAssistExecutorPriority(job,executor,engie)
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
        -- Precondition: structure is not dead!
        local start = PROFILER:Now()
        structure.FlowAI.ProductionAssigned = false
        local bestJob = nil
        local bestPriority = SMALL_NEGATIVE
        local upgradeJob = false
        for _, job in self.factoryJobs do
            local priority = self:StartExecutorPriority(job,structure)
            if priority > bestPriority then
                bestJob = job
                bestPriority = priority
            end
        end
        for _, job in self.upgradeJobs do
            local priority = self:StartExecutorPriority(job,structure)
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

    StartExecutorPriority = function(self,job,builder)
        -- Return the priority for starting an executor for 'job' with 'builder'.  Negative priority means this job should not be attempted.
        -- TODO: Swap to better estimates using actual and theoretical mass spends
        -- Check if this job can be made by this builder
        local bp = builder:GetBlueprint()
        -- Check if the builder meets the specified builder in the job
        if job.specification.builderBlueprintID and (not job.specification.builderBlueprintID == bp.BlueprintId) then
            return -1
        end
        -- Check if we are going to exceed the number of allowed jobs of this type
        if job.data.numExecutors >= job.specification.duplicates then
            return -1
        end
        -- Check if we're going to make too many things of this type
        if job.data.numExecutors >= job.specification.count then
            return -1
        end
        -- Check if the builder can build this thing
        if not builder:CanBuild(job.specification.unitBlueprintID) then
            return -1
        end
        -- TODO: Check component requirements here
        -- Calculate and return priority of this job.  Spend requirement checking is implicit (TODO).
        if job.specification.prioritySwitch then
            return 1 - (job.data.numExecutors+1)/math.min(job.specification.count,job.specification.duplicates) - SMALL_NEGATIVE
        else
            return 1 - ((job.data.totalBuildpower+bp.Economy.BuildRate)*job.data.massSpendRate)/job.specification.targetSpend - SMALL_NEGATIVE
        end
    end,

    StartAssistExecutorPriority = function(self,job,executor,engie)
        -- Return the priority for assisting 'executor' with 'engie' (under the given job).
        -- TODO: Check assist ratio
        -- TODO: Check job proximity
        -- TODO: Remove upscaling bodge job
        -- Check if this job allows assists
        if not job.specification.assist then
            return -1
        end
        -- Check job hasn't yet finished
        if executor.complete then
            return -1
        end
        local bp = engie:GetBlueprint()
        -- Calculate and return priority of this job.  Spend requirement checking is implicit (TODO).
        if job.specification.prioritySwitch then
            return 1.1*(1 - job.data.numExecutors/math.min(job.specification.count,job.specification.duplicates) - SMALL_NEGATIVE)
        else
            return 1.1*(1 - ((job.data.totalBuildpower+bp.Economy.BuildRate)*job.data.massSpendRate)/job.specification.targetSpend - SMALL_NEGATIVE)
        end
    end,

    FindBuildLocation = function(self,job,engie)
        local initLocation = job.specification.location
        if not initLocation then
            local pos = engie:GetPosition()
            return self.brain.deconfliction:FindBuildCoordinates({math.round(pos[1]) + Random(-3,3) + 0.5,0,math.round(pos[3]) + Random(-3,3) + 0.5},job.specification.unitBlueprintID,self.brain.aiBrain)
        else
            local pos = engie:GetPosition()
            local delta = {initLocation.x - pos[1], initLocation.z - pos[3]}
            local dist = math.sqrt(delta[1]*delta[1] + delta[2]*delta[2])
            local norm = math.min(initLocation.radius/dist,1)
            return self.brain.deconfliction:FindBuildCoordinates({initLocation.x+delta[1]*norm + Random(-3,3) + 0.5,0,initLocation.z+delta[2]*norm + Random(-3,3) + 0.5},job.specification.unitBlueprintID,self.brain.aiBrain)
        end
    end,

    FindMarkerBuildLocation = function(self,job,engie)
        return 
    end,

    StartMobileExecutor = function(self,job,engie)
        -- Given an engineer and a job to start, create an executor (and maintain associated state).
        local executor = MobileJobExecutor()
        local buildLocation = nil
        local buildID = nil
        if job.specification.markerType then
            buildID = self.brain.markerManager:GetClosestMarker(engie:GetPosition(),job.specification.markerType,engie)
            buildLocation = self.brain.markerManager:RegisterMarker(buildID)
        else
            buildLocation = self:FindBuildLocation(job,engie)
            buildID = self.brain.deconfliction:Register(buildLocation,GetUnitBlueprintByName(job.specification.unitBlueprintID))
        end
        if not buildLocation then
            WARN("Build location not found for: "..tostring(job.specification.unitBlueprintID))
            return
        end
        engie.FlowAI.ProductionAssigned = true
        executor:Init(engie,job,buildLocation,buildID,self.brain)
        job.data.numExecutors = job.data.numExecutors + 1
        job.data.executors[job.data.numExecutors] = executor
        executor:Run()
    end,

    StartFactoryExecutor = function(self,job,factory)
        -- Given an factory and a job to start, create an executor (and maintain associated state).
        local executor = FactoryJobExecutor()
        executor:Init(factory,job,self.brain)
        job.data.numExecutors = job.data.numExecutors + 1
        job.data.executors[job.data.numExecutors] = executor
        executor:Run()
    end,

    StartUpgradeExecutor = function(self,job,structure)
        -- Given a structure and a job to start, create an executor (and maintain associated state).
        local executor = UpgradeJobExecutor()
        structure.FlowAI.ProductionAssigned = true
        executor:Init(structure,job,self.brain)
        job.data.numExecutors = job.data.numExecutors + 1
        job.data.executors[job.data.numExecutors] = executor
        executor:Run()
    end,

    AssistExecutor = function(self,job,executor,engie)
        -- Get an engie to assist an existing executor
        engie.FlowAI.ProductionAssigned = true
        executor:AddEngineer(engie)
    end,

    ControlThread = function(self)
        -- Global coordinator of stuff.
        local i = 0
        while self.brain:IsAlive() do
            self:ExecutorMonitoring()
            self:JobMonitoring()
            if math.mod(i,20) == 0 then
                -- Every X ticks reassign idle stuff to jobs where possible
                self:JobDistribution()
            end
            i = i+1
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