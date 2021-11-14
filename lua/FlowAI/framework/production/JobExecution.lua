--[[
    Execution of individual jobs
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

JobExecutor = Class({
    -- Add support for assists here
    Init = function(self,builder,toBuildID)
    end,

    GetSpendStats = function(self)
    end,
})

MobileJobExecutor = Class(JobExecutor) {
    Init = function(self,builder,toBuildID,buildLocation,deconflicter,commandInterface,brain)
        self.brain = brain
        -- Some flags we'll need
        self.complete = false
        self.success = false
        -- Completion explanation (for debugging)
        self.reason = nil
        -- The thing we're building - while this is nil we assume the job is unstarted
        self.target = nil
        self.toBuildID = toBuildID
        -- The engie that can start the jobs
        self.builder = builder
        -- The engie to assist (if not the target)
        self.mainEngie = builder
        -- The place to buildLocation
        self.buildLocation = buildLocation
        -- Build location deconfliction
        self.deconflicter = deconflicter
        -- Command Interface
        self.commandInterface = commandInterface
        -- All engies excepting the main engie
        self.subsidiaryEngies = {}
        self.numEngies = 1
    end,

    AddEngineer = function(self,assister)
        self.subsidiaryEngies[self.numEngies] = assister
        self.numEngies = self.numEngies + 1
    end,

    GetEstimatedCompletionTime = function(self,includeBottlenecks)
        -- TODO
    end,

    ReduceSpend = function(self,targetSpend)
        -- TODO
    end,

    JobThread = function(self)
        local start = PROFILER:Now()
        local reissue = true
        local started = false
        -- Initialise job
        self.deconflicter:Register(self.buildLocation,GetUnitBlueprintByName(self.toBuildID))
        self.commandInterface:IssueBuildMobile({self.mainEngie},self.buildLocation,self.toBuildID)
        PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
        WaitTicks(1)
        while (not self.complete) and (self.numEngies > 0 or self.target) do
            WaitTicks(1)
            start = PROFILER:Now()
            -- Try to update self.target.
            if (not self.target) and self.mainEngie.UnitBeingBuilt then
                self.target = self.mainEngie.UnitBeingBuilt
                started = true
            end
            -- If target destroyed then complete with failure
            if started and ((not self.target) or self.target.Dead) then
                self.complete = true
                self.success = false
                self.reason = "Target was destroyed."
            end
            -- Iterate through self.subsidiaryEngies deleting dead things.
            if self.numEngies > 1 then
                local i = 1
                while i < self.numEngies do
                    if (not self.subsidiaryEngies[i]) or self.subsidiaryEngies[i].Dead then
                        self.numEngies = self.numEngies - 1
                        if i < self.numEngies then
                            self.subsidiaryEngies[i] = self.subsidiaryEngies[self.numEngies]
                        end
                    else
                        i = i + 1
                    end
                end
            end
            -- If main engie is dead, replace it if possible.
            if (self.numEngies > 0) and ((not self.mainEngie) or self.mainEngie.Dead) then
                if self.target then
                    if self.numEngies > 1 then
                        self.numEngies = self.numEngies - 1
                        self.mainEngie = self.subsidiaryEngies[self.numEngies]
                         -- Commented out below as unecessary, this will tidy up on it's own.
                        --self.subsidiaryEngies[self.numEngies] = nil
                    else
                        self.numEngies = 0
                    end
                else
                    -- Main engie died without starting the job.  Any replacement main engie may not be able to build the intended job, so we have to fail.
                    self.complete = true
                    self.success = false
                    self.reason = "Main engie died without starting job."
                end
            end
            if self.target and (not self.target.Dead) and (not self.target:IsBeingBuilt()) then
                -- Check if we've finished
                self.complete = true
                self.success = true
                self.reason = "Target complete."
            end
            --[[
                Invariants here:
                self.complete == false =>
                    - All subsidiary engies are alive
                    - Only one of the following is true:
                        - Main engie is alive
                        - Target exists AND num engies is 0
            ]]
            if (not self.complete) and (self.numEngies > 0) then
                -- Check if main engie is idle.  Try a single order re-issue if it is, otherwise fail.
                if (not self.target) and self.mainEngie:IsIdleState() then
                    if reissue then
                        self.commandInterface:IssueBuildMobile({self.mainEngie},self.buildLocation,self.toBuildID)
                        reissue = false
                    else
                        self.complete = true
                        self.success = false
                        self.reason = "Order reissue limit exceeded."
                    end
                end
                -- Iterate through self.subsidiaryEngies checking for idleness.
                local i = 1
                local idleEngies = {}
                local idleFound = false
                while i < self.numEngies do
                    if self.subsidiaryEngies[i]:IsIdleState() then
                        idleFound = true
                        table.insert(idleEngies,self.subsidiaryEngies[i])
                    end
                    i = i + 1
                end
                if idleFound and self.target then
                    self.commandInterface:IssueRepair(self.idleEngies,self.target)
                elseif idleFound then
                    self.commandInterface:IssueGuard(self.idleEngies,self.mainEngie)
                end
            end
            PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
            WaitTicks(1)
        end
        start = PROFILER:Now()
        self.deconflicter:Clear(self.buildLocation)
        PROFILER:Add("MobileJobExecutor:JobThread",PROFILER:Now()-start)
    end,

    Run = function(self)
        self:ForkThread(self.JobThread)
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
}

FactoryJobExecutor = Class(JobExecutor) {

}

UpgradeJobExecutor = Class(JobExecutor) {

}


-- Interface functions

function CreateMobileJob(builder,toBuildID,location)
    -- TODO
end
