--[[
    Execution of individual jobs
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

JobExecutor = Class({
    Init = function(self,builder,job,brain)
        -- The job we're doing.  This class is responsible for some state maintenance here.
        self.job = job
        -- Somwhere to dump old threads
        self.trash = brain.trash
        -- Some flags we'll need
        self.complete = false
        self.success = false
        self.started = false
        -- Completion explanation (for debugging)
        self.reason = nil
        -- The thing we're building - while this is nil we assume the job is unstarted
        self.target = nil
        self.toBuildID = job.specification.unitBlueprintID
        -- The builder to assist (if not the target)
        self.mainBuilder = builder
        self.builderRate = builder:GetBuildRate()
        -- Command Interface
        self.commandInterface = brain.commandInterface
        -- All engies excepting the main engie
        self.subsidiaryEngies = {}
        self.buildRates = {}
        self.numEngies = 1

        -- Update job state here
        self.job.data.totalBuildpower = self.job.data.totalBuildpower + self.builderRate
        -- Actual spend is measured assuming 100% efficiency - i.e. we're not in a stall.
        self.actualSpend = 0
        -- Theoretical spend includes engies which aren't building right now, but should be at some point.
        self.theoreticalSpend = 0
    end,

    AddEngineer = function(self,assister)
        self.subsidiaryEngies[self.numEngies] = assister
        local buildRate = assister:GetBuildRate()
        self.buildRates[self.numEngies] = buildRate
        self.numEngies = self.numEngies + 1
        self.job.data.totalBuildpower = self.job.data.totalBuildpower + buildRate
        self.job.data.assistBuildpower = self.job.data.assistBuildpower + buildRate
        -- If the engie is already doing something, stop.  Then we know to pick it up later and issue a new order.
        self.commandInterface:IssueStop({assister})
    end,

    GetEstimatedCompletionTime = function(self,includeBottlenecks)
        -- TODO
    end,

    ReduceSpend = function(self,targetSpend)
        -- TODO
    end,

    CompleteJob = function(self)
        -- Called (by distribution layer) after completion, but not necessarily before the job thread ends.
        -- Responsible for removing this executor's resources from the job state.
        if self.success then
            self.job.specification.count = self.job.specification.count - 1
        else
            WARN('Job failed for reason: '..tostring(self.reason))
        end
        self.job.data.totalBuildpower = self.job.data.totalBuildpower - self.builderRate
        local i = 1
        while i < self.numEngies do
            self.job.data.totalBuildpower = self.job.data.totalBuildpower - self.buildRates[i]
            self.job.data.assistBuildpower = self.job.data.assistBuildpower - self.buildRates[i]
        end
    end,

    ClearDeadAssisters = function(self)
        -- Iterate through self.subsidiaryEngies deleting dead things.
        if self.numEngies > 1 then
            local i = 1
            while i < self.numEngies do
                if (not self.subsidiaryEngies[i]) or self.subsidiaryEngies[i].Dead then
                    self.numEngies = self.numEngies - 1
                    if i < self.numEngies then
                        self.subsidiaryEngies[i] = self.subsidiaryEngies[self.numEngies]
                        self.job.data.totalBuildpower = self.job.data.totalBuildpower - self.buildRates[i]
                        self.job.data.assistBuildpower = self.job.data.assistBuildpower - self.buildRates[i]
                        self.buildRates[i] = self.buildRates[self.numEngies]
                        -- Commented out below as unecessary, this will tidy up on it's own.
                        --self.subsidiaryEngies[self.numEngies] = nil
                    end
                else
                    i = i + 1
                end
            end
        end
    end,

    ResetSpendStats = function(self)
        self.actualSpend = 0
        self.theoreticalSpend = 0
    end,

    CheckAssistingEngies = function(self)
        -- Iterate through self.subsidiaryEngies checking for idleness, and recording stats.
        local i = 1
        local idleEngies = {}
        local idleFound = false
        while i < self.numEngies do
            if self.subsidiaryEngies[i]:IsIdleState() then
                idleFound = true
                table.insert(idleEngies,self.subsidiaryEngies[i])
            elseif not self.subsidiaryEngies[i]:IsMoving() then
                -- Assume we're building if we're stationary and not idle?
                self.actualSpend = self.actualSpend + self.buildRates[i] * self.job.data.massSpendRate
            end
            self.theoreticalSpend = self.theoreticalSpend + self.buildRates[i] * self.job.data.massSpendRate
            i = i + 1
        end
        if idleFound then
            self.commandInterface:IssueGuard(self.idleEngies,self.mainBuilder)
        end
    end,

    CheckTarget = function(self)
        -- Try to update self.target.
        if (not self.target) and self.mainBuilder.UnitBeingBuilt then
            self.target = self.mainBuilder.UnitBeingBuilt
            self.started = true
        end
        -- If target destroyed then complete with failure
        if self.started and ((not self.target) or self.target.Dead) then
            self.complete = true
            self.success = false
            self.reason = "Target was destroyed."
        end
        if self.target and (not self.target.Dead) and (not self.target:IsBeingBuilt()) then
            -- Check if we've finished
            self.complete = true
            self.success = true
            self.reason = "Target complete."
        end
    end,

    Run = function(self)
        self:ForkThread(self.JobThread)
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

MobileJobExecutor = Class(JobExecutor){
    Init = function(self,builder,job,buildLocation,brain)
        JobExecutor.Init(self,builder,job,brain)
        -- Some more flags we'll need
        self.reissue = true
        -- The place to buildLocation
        self.buildLocation = buildLocation
        -- Build location deconfliction
        self.deconfliction = brain.deconfliction
        self.buildID = nil
    end,

    ClearDeadBuilders = function(self)
        self:ClearDeadAssisters()
        -- If main engie is dead, replace it if possible.
        if (self.numEngies > 0) and ((not self.mainBuilder) or self.mainBuilder.Dead) then
            if self.target then
                if self.numEngies > 1 then
                    self.numEngies = self.numEngies - 1
                    self.mainBuilder = self.subsidiaryEngies[self.numEngies]
                    self.job.data.totalBuildpower = self.job.data.totalBuildpower - self.builderRate
                    self.job.data.assistBuildpower = self.job.data.assistBuildpower - self.buildRates[self.numEngies]
                    -- Commented out below as unecessary, this will tidy up on it's own.
                    --self.subsidiaryEngies[self.numEngies] = nil
                else
                    self.numEngies = 0
                end
            else
                -- Main builder died without starting the job.  Any replacement main builder may not be able to build the intended job, so we have to fail.
                self.complete = true
                self.success = false
                self.reason = "Main builder died without starting job."
            end
        end
    end,

    CheckMainBuilder = function(self)
        -- Check if main engie is idle.  Try a single order re-issue if it is, otherwise fail.
        if (not self.target) and self.mainBuilder:IsIdleState() then
            if self.reissue then
                self.commandInterface:IssueBuildMobile({self.mainBuilder},self.buildLocation,self.toBuildID)
                self.reissue = false
            else
                self.complete = true
                self.success = false
                self.reason = "Order reissue limit exceeded."
            end
        end
        self.theoreticalSpend = self.theoreticalSpend + self.builderRate * self.job.data.massSpendRate
        if self.mainBuilder:IsUnitState('Building') or self.mainBuilder:IsUnitState('Repairing') then
            self.actualSpend = self.actualSpend + self.builderRate * self.job.data.massSpendRate
        end
    end,

    JobThread = function(self)
        local start = PROFILER:Now()
        -- Initialise job
        self.buildID = self.deconfliction:Register(self.buildLocation,GetUnitBlueprintByName(self.toBuildID))
        self.commandInterface:IssueBuildMobile({self.mainBuilder},self.buildLocation,self.toBuildID)
        PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
        WaitTicks(1)
        while (not self.complete) and (self.numEngies > 0 or self.target) do
            WaitTicks(1)
            start = PROFILER:Now()
            -- Clear out dead engies
            self:ClearDeadBuilders()
            -- Check relevant target info
            if not self.complete then
                self:CheckTarget()
            end
            --[[
                Invariants here:
                self.complete == false =>
                    - All subsidiary engies are alive
                    - Only one of the following is true:
                        - Main engie is alive
                        - Target exists AND num engies is 0
            ]]
            -- Reset spend stats to 0 before we work them all out again.
            self:ResetSpendStats()
            if (not self.complete) and (self.numEngies > 0) then
                -- Not finished, and we have a main engie
                self:CheckMainBuilder()
                self:CheckAssistingEngies()
            end
            PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
            WaitTicks(1)
        end
        start = PROFILER:Now()
        self.deconfliction:Clear(self.buildID)
        PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
    end,
}

FactoryJobExecutor = Class(JobExecutor){
    ClearDeadBuilders = function(self)
        self:ClearDeadAssisters()
        if (self.numEngies > 0) and ((not self.mainBuilder) or self.mainBuilder.Dead) then
            -- Factory died without during the job.
            self.complete = true
            self.success = false
            self.reason = "Factory died during job."
        end
    end,

    CheckTarget = function(self)
        -- Try to update self.target.
        if (not self.target) and (self.mainBuilder.UnitBeingBuilt ~= self.mainBuilder.FlowAI.previousBuilt) then
            self.target = self.mainBuilder.UnitBeingBuilt
            -- Cache this, because it doesn't update until a new unit starts (which is effing annoying)
            self.mainBuilder.FlowAI.previousBuilt = self.mainBuilder.UnitBeingBuilt
            self.started = true
        end
        -- If target destroyed then complete with failure
        if self.started and ((not self.target) or self.target.Dead) then
            self.complete = true
            self.success = false
            self.reason = "Target was destroyed."
        end
        if self.target and (not self.target.Dead) and (not self.target:IsBeingBuilt()) then
            -- Check if we've finished
            self.complete = true
            self.success = true
            self.reason = "Target complete."
        end
    end,

    CheckMainBuilder = function(self)
        -- Check if main builder is idle.  Try a single order re-issue if it is, otherwise fail.
        if self.mainBuilder:IsIdleState() and (not self.mainBuilder:GetCommandQueue()[1]) then
            self.complete = true
            self.success = false
            self.reason = "Unknown problem - factory found idle."
        end
        self.theoreticalSpend = self.theoreticalSpend + self.builderRate * self.job.data.massSpendRate
        if not self.mainBuilder:IsIdleState() then
            self.actualSpend = self.actualSpend + self.builderRate * self.job.data.massSpendRate
        end
    end,

    JobThread = function(self)
        local start = PROFILER:Now()
        -- Initialise job
        self.commandInterface:IssueBuildFactory({self.mainBuilder},self.toBuildID,1)
        PROFILER:Add("FactoryJobExecutor:JobThread",PROFILER:Now()-start)
        WaitTicks(1)
        while not self.complete do
            WaitTicks(1)
            start = PROFILER:Now()
            -- Clear out dead engies
            self:ClearDeadBuilders()
            -- Check relevant target info
            if not self.complete then
                self:CheckTarget()
            end
            --[[
                Invariants here:
                self.complete == false =>
                    - All subsidiary engies are alive
                    - Main builder is alive
            ]]
            -- Reset spend stats to 0 before we work them all out again.
            self:ResetSpendStats()
            if (not self.complete) and (self.numEngies > 0) then
                -- Not finished, and we have a main engie
                self:CheckMainBuilder()
                self:CheckAssistingEngies()
            end
            PROFILER:Add("FactoryJobExecutor:JobThread",PROFILER:Now()-start)
            WaitTicks(1)
        end
    end,
}

UpgradeJobExecutor = Class(JobExecutor){
    ClearDeadBuilders = function(self)
        self:ClearDeadAssisters()
        if (self.numEngies > 0) and ((not self.mainBuilder) or self.mainBuilder.Dead) then
            -- Structure died without during the job.
            self.complete = true
            self.success = false
            self.reason = "Structure died during upgrade."
        end
    end,

    CheckTarget = function(self)
        -- Try to update self.target.
        if (not self.target) and (self.mainBuilder.UnitBeingBuilt ~= self.mainBuilder.FlowAI.previousBuilt) then
            self.target = self.mainBuilder.UnitBeingBuilt
            -- Cache this, because it doesn't update until a new unit starts (which is effing annoying)
            self.mainBuilder.FlowAI.previousBuilt = self.mainBuilder.UnitBeingBuilt
            self.started = true
        end
        -- If target destroyed then complete with failure
        if self.started and ((not self.target) or self.target.Dead) then
            self.complete = true
            self.success = false
            self.reason = "Target was destroyed."
        end
        if self.target and (not self.target.Dead) and (not self.target:IsBeingBuilt()) then
            -- Check if we've finished
            self.complete = true
            self.success = true
            self.reason = "Target complete."
        end
    end,

    CheckMainBuilder = function(self)
        -- Check if main builder is idle.  Try a single order re-issue if it is, otherwise fail.
        if self.mainBuilder:IsIdleState() and (not self.mainBuilder:GetCommandQueue()[1]) then
            self.complete = true
            self.success = false
            self.reason = "Unknown problem - structure found idle."
        end
        self.theoreticalSpend = self.theoreticalSpend + self.builderRate * self.job.data.massSpendRate
        if not self.mainBuilder:IsIdleState() then
            self.actualSpend = self.actualSpend + self.builderRate * self.job.data.massSpendRate
        end
    end,

    JobThread = function(self)
        local start = PROFILER:Now()
        -- Initialise job
        self.commandInterface:IssueUpgrade({self.mainBuilder},self.toBuildID)
        PROFILER:Add("UpgradeJobExecutor:JobThread",PROFILER:Now()-start)
        WaitTicks(1)
        while not self.complete do
            WaitTicks(1)
            start = PROFILER:Now()
            -- Clear out dead engies
            self:ClearDeadBuilders()
            -- Check relevant target info
            if not self.complete then
                self:CheckTarget()
            end
            --[[
                Invariants here:
                self.complete == false =>
                    - All subsidiary engies are alive
                    - Main builder is alive
            ]]
            -- Reset spend stats to 0 before we work them all out again.
            self:ResetSpendStats()
            if (not self.complete) and (self.numEngies > 0) then
                -- Not finished, and we have a main engie
                self:CheckMainBuilder()
                self:CheckAssistingEngies()
            end
            PROFILER:Add("UpgradeJobExecutor:JobThread",PROFILER:Now()-start)
            WaitTicks(1)
        end
    end,
}