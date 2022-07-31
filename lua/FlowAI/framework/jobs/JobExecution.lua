--[[
    In this file, we implement JobExecutor classes to handle the in-game execution of WorkItems.
    Job executors are responsible for running a job by issuing orders and maintaining some state (e.g. buildpower assigned).
    They must handle the addition of new engineers, and provide best efforts to complete jobs despite destruction of assigned builders.
]]

local CheckForEnemyStructure = import('/mods/DilliDalli/lua/FlowAI/framework/Intel.lua').CheckForEnemyStructure
local CreateWorkLimiter = import('/mods/DilliDalli/lua/FlowAI/framework/utils/WorkLimits.lua').CreateWorkLimiter

local BUILDPOWER_MODIFIER = 0.5

JobExecutor = Class({
    Init = function(self,brain,builder,blueprintID)
        self.brain = brain
        -- Some flags we'll need
        self.complete = false
        self.success = false
        self.started = false
        -- Completion explanation (for debugging)
        self.reason = nil
        -- The thing we're building - while this is nil we assume the job is unstarted
        self.target = nil
        self.toBuildID = blueprintID
        -- The builder to assist (if not the target)
        self.mainBuilder = builder
        self.builderRate = builder:GetBuildRate()
        -- Command Interface
        self.commandInterface = brain.commandInterface
        -- All engies excepting the main engie
        self.subsidiaryEngies = {}
        self.buildRates = {}
        self.numEngies = 1
        -- Assigned buildpower
        self.buildpower = self.builderRate

        -- Record job type
        self.isMobile = false
        self.isFactory = false
        self.isUpgrade = false

        -- Make sure the builder is ready to go
        self.commandInterface:IssueStop({self.mainBuilder})
    end,

    AddEngineer = function(self,assister)
        self.subsidiaryEngies[self.numEngies] = assister
        local buildRate = assister:GetBuildRate()
        self.buildRates[self.numEngies] = buildRate
        self.numEngies = self.numEngies + 1
        self.buildpower = self.buildpower+buildRate
        -- If the engie is already doing something, stop.  Then we know to pick it up later and issue a new order.
        self.commandInterface:IssueStop({assister})
    end,

    CompleteJob = function(self)
        -- Called after completion, but not necessarily before the job thread ends.
        if not self.success then
            WARN('Job failed for reason: '..tostring(self.reason))
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
                        self.buildRates[i] = self.buildRates[self.numEngies]
                        self.subsidiaryEngies[i].executorIndex = i
                        self.subsidiaryEngies[self.numEngies] = nil
                    end
                else
                    i = i + 1
                end
            end
        end
    end,

    ResetSpendStats = function(self) self.buildpower = 0 end,
    GetBuildpower = function(self) return self.buildpower end,

    CheckAssistingEngies = function(self)
        -- Iterate through self.subsidiaryEngies checking for idleness, and recording stats.
        local i = 1
        local idleEngies = {}
        local idleFound = false
        while i < self.numEngies do
            if self.subsidiaryEngies[i]:IsIdleState() then
                idleFound = true
                table.insert(idleEngies,self.subsidiaryEngies[i])
                self.buildpower = self.buildpower + self.buildRates[i] * BUILDPOWER_MODIFIER
            elseif not self.subsidiaryEngies[i]:IsMoving() then
                -- Assume we're building if we're stationary and not idle?
                self.buildpower = self.buildpower + self.buildRates[i]
            else
                self.buildpower = self.buildpower + self.buildRates[i] * BUILDPOWER_MODIFIER
            end
            i = i + 1
        end
        if idleFound then
            self.commandInterface:IssueGuard(idleEngies,self.mainBuilder)
        end
    end,

    Run = function(self)
        self.brain:ForkThread(self, self.JobThread)
    end,
})

MobileJobExecutor = Class(JobExecutor){
    Init = function(self,brain,builder,blueprintID,buildLocation)
        JobExecutor.Init(self,brain,builder,blueprintID)
        -- Some more flags we'll need
        self.reissue = true
        -- Build location deconfliction / marker management
        self.buildLocation = buildLocation
        self.isMobile = true
    end,

    GetPosition = function(self) return self.buildLocation end,

    ClearDeadBuilders = function(self)
        self:ClearDeadAssisters()
        -- If main engie is dead, replace it if possible.
        if (self.numEngies > 0) and ((not self.mainBuilder) or self.mainBuilder.Dead) then
            if self.target then
                if self.numEngies > 1 then
                    self.numEngies = self.numEngies - 1
                    self.mainBuilder = self.subsidiaryEngies[self.numEngies]
                    self.subsidiaryEngies[self.numEngies] = nil
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

    CheckMainBuilder = function(self)
        -- Check if main engie is idle.  Try a single order re-issue if it is, otherwise fail.
        if (not self.target) and self.mainBuilder:IsIdleState() then
            -- Check to see if there's an enemy building on that spot to reclaim
            local unit = CheckForEnemyStructure(self.brain.aiBrain,self.buildLocation,0.2)
            if unit then
                self.commandInterface:IssueReclaim({self.mainBuilder},unit)
            elseif self.reissue then
                self.commandInterface:IssueBuildMobile({self.mainBuilder},self.buildLocation,self.toBuildID)
                self.reissue = false
            else
                self.complete = true
                self.success = false
                self.reason = "Order reissue limit exceeded."
            end
        end
        -- TODO: downweight builderRate if builder is still en-route
        self.buildpower = self.buildpower + self.builderRate
    end,

    JobThread = function(self)
        local workLimiter = CreateWorkLimiter(1,"MobileJobExecutor:JobThread")
        -- Initialise job
        self.commandInterface:IssueBuildMobile({self.mainBuilder},self.buildLocation,self.toBuildID)
        workLimiter:WaitTicks(1)
        while (not self.complete) and (self.numEngies > 0 or self.target) do
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
            workLimiter:WaitTicks(2)
        end
        workLimiter:End()
    end,
}

FactoryJobExecutor = Class(JobExecutor){
    Init = function(self,brain,builder,blueprintID)
        JobExecutor.Init(self,brain,builder,blueprintID)
        self.pos = table.copy(builder:GetPosition())
        self.isFactory = true
    end,

    GetPosition = function(self) return self.pos end,

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
        if (not self.target) and (self.mainBuilder.UnitBeingBuilt ~= self.mainBuilder.FlowAI.jobData.previousBuilt) then
            self.target = self.mainBuilder.UnitBeingBuilt
            -- Cache this, because it doesn't update until a new unit starts (which is effing annoying)
            self.mainBuilder.FlowAI.jobData.previousBuilt = self.mainBuilder.UnitBeingBuilt
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
        -- Check if main builder is idle.
        if self.mainBuilder:IsIdleState() and (not self.mainBuilder:GetCommandQueue()[1]) then
            self.complete = true
            self.success = false
            self.reason = "Unknown problem - factory found idle."
        end
        self.buildpower = self.buildpower + self.builderRate
    end,

    JobThread = function(self)
        local workLimiter = CreateWorkLimiter(1,"FactoryJobExecutor:JobThread")
        -- Initialise job
        self.commandInterface:IssueBuildFactory({self.mainBuilder},self.toBuildID,1)
        workLimiter:WaitTicks(1)
        while not self.complete do
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
            workLimiter:WaitTicks(2)
        end
        workLimiter:End()
    end,
}

UpgradeJobExecutor = Class(JobExecutor){
    Init = function(self,brain,builder,blueprintID)
        JobExecutor.Init(self,brain,builder,blueprintID)
        self.pos = table.copy(builder:GetPosition())
        self.isUpgrade = true
    end,

    GetPosition = function(self) return self.pos end,

    ClearDeadBuilders = function(self)
        self:ClearDeadAssisters()
        if (self.numEngies > 0) and ((not self.mainBuilder) or self.mainBuilder.Dead) and ((not self.target) or self.target.Dead) then
            -- Structure died without during the job.
            self.complete = true
            self.success = false
            self.reason = "Structure died during upgrade."
        end
    end,

    CheckTarget = function(self)
        -- Try to update self.target.
        if (not self.target) and (self.mainBuilder.UnitBeingBuilt ~= self.mainBuilder.FlowAI.jobData.previousBuilt) then
            self.target = self.mainBuilder.UnitBeingBuilt
            -- Cache this, because it doesn't update until a new unit starts (which is effing annoying)
            self.mainBuilder.FlowAI.jobData.previousBuilt = self.mainBuilder.UnitBeingBuilt
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
        self.buildpower = self.buildpower + self.builderRate
    end,

    JobThread = function(self)
        local workLimiter = CreateWorkLimiter(1,"UpgradeJobExecutor:JobThread")
        -- Initialise job
        self.commandInterface:IssueUpgrade({self.mainBuilder},self.toBuildID)
        workLimiter:WaitTicks(1)
        while not self.complete do
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
            workLimiter:WaitTicks(2)
        end
        workLimiter:End()
    end,
}