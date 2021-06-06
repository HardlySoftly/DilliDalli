local TroopFunctions = import('/mods/DilliDalli/lua/AI/DilliDalli/TroopFunctions.lua')
local Translation = import('/mods/DilliDalli/lua/AI/DilliDalli/FactionCompatibility.lua').translate

BaseController = Class({
    Initialise = function(self,brain)
        self.brain = brain

        self.jobID = 0

        self.numMobileJobs = 0
        self.mobileJobs = {}

        self.numFactoryJobs = 0
        self.factoryJobs = {}

        self.numIdle = 0
        self.idle = {}
    end,

    CreateGenericJob = function(self)
        return {
            -- The thing to build
            work = nil,
            -- How important is it?
            priority = 0,
            -- Do we have a target location?
            location = nil,
            -- If we have a location, within what distance does the thing need building in?
            distance = 0,
            -- How much mass do we want to spend on this (through assistance only)?
            targetSpend = 0,
            -- Is this part of the initial build order?
            buildOrder = false,
            -- How many of these things to make? -1 => Inf
            count = 1,
            -- How many duplicates of this job to allow.  -1 => Inf
            duplicates = 1,
            -- Keep while count == 0?  (e.g. long standing tasks that the brain may want to update)
            keep = false,
        }
    end,

    AddMobileJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, id=self.jobID, activeCount=0 }
        self.jobID = self.jobID + 1
        self.numMobileJobs = self.numMobileJobs + 1
        self.mobileJobs[self.numMobileJobs] = { job = job, meta=meta }
    end,
    AddFactoryJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, id=self.jobID, activeCount=0 }
        self.jobID = self.jobID + 1
        self.numFactoryJobs = self.numFactoryJobs + 1
        self.factoryJobs[self.numFactoryJobs] = { job = job, meta=meta }
    end,

    OnCompleteMobile = function(self,jobID)
        -- Delete a job
        local index
        for i, job in self.mobileJobs do
            if job.meta.id == jobID then
                job.job.count = job.job.count - 1
                job.meta.activeCount = job.meta.activeCount - 1
                -- TODO: support assisting
                index = i
            end
        end
        if index and (not self.mobileJobs[index].job.keep) and self.mobileJobs[index].meta.activeCount == 0 and self.mobileJobs[index].job.count == 0 then
            table.remove(self.mobileJobs,index)
        end
    end,

    OnCompleteFactory = function(self,jobID)
        -- Delete a job
        local index
        for i, job in self.factoryJobs do
            if job.meta.id == jobID then
                job.job.count = job.job.count - 1
                job.meta.activeCount = job.meta.activeCount - 1
                index = i
            end
        end
        if index and (not self.factoryJobs[index].job.keep) and self.factoryJobs[index].meta.activeCount == 0 and self.factoryJobs[index].job.count == 0 then
            table.remove(self.factoryJobs,index)
        end
    end,

    CanDoJob = function(self,unit,job)
        -- Used for both Engineers and Factories
        return (
            job.meta.activeCount < job.job.duplicates
            and job.meta.activeCount < job.job.count
            and unit:CanBuild(Translation[job.job.work][unit.factionCategory])
        )
    end,

    AssignJobMobile = function(self,engie,job)
        job.meta.activeCount = job.meta.activeCount + 1
        -- Set a flag to tell everyone this engie is busy
        if not engie.CustomData then
            engie.CustomData = {}
        end
        engie.CustomData.engieAssigned = true
        self:ForkThread(self.RunMobileJobThread,job,engie,false)
    end,

    AssignJobFactory = function(self,fac,job)
        job.meta.activeCount = job.meta.activeCount + 1
        -- Set a flag to tell everyone this fac is busy
        if not fac.CustomData then
            fac.CustomData = {}
        end
        fac.CustomData.facAssigned = true
        self:ForkThread(self.RunFactoryJobThread,job,fac,false)
    end,

    IdentifyJob = function(self,unit,jobs)
        local bestJob
        local bestPriority = 0
        local isBOJob = false
        for i=1,table.getn(jobs) do
            local job = jobs[i]
            -- TODO: Support assitance
            if self:CanDoJob(unit,job) and ((job.job.priority > bestPriority and isBOJob == job.job.buildOrder) or (not isBOJob and job.job.buildOrder)) then
                bestPriority = job.job.priority
                bestJob = job
                isBOJob = job.job.buildOrder
            end
        end
        return bestJob
    end,

    AssignEngineers = function(self,allEngies)
        for i=1,table.getn(allEngies) do
            local job = self:IdentifyJob(allEngies[i],self.mobileJobs)
            if job then
                self:AssignJobMobile(allEngies[i],job)
            end
        end
    end,

    AssignFactories = function(self,allFacs)
        for i=1,table.getn(allFacs) do
            local job = self:IdentifyJob(allFacs[i],self.factoryJobs)
            if job then
                self:AssignJobFactory(allFacs[i],job)
            end
        end
    end,

    RunMobileJobThread = function(self,job,engie,assist)
        -- TODO: Support assistance
        local activeJob = job
        while activeJob do
            --job.meta.assigned[table.getn(job.meta.assigned)+1] = engie
            local unitID = Translation[activeJob.job.work][engie.factionCategory]
            -- Build the thing
            if activeJob.job.work == "MexT1" or activeJob.job.work == "MexT2" or activeJob.job.work == "MexT3" then
                TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Mass")
            elseif activeJob.job.work == "Hydro" then
                TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Hydrocarbon")
            else
                TroopFunctions.EngineerBuildStructure(self.brain,engie,unitID)
            end
            -- Return engie back to the pool
            self:OnCompleteMobile(activeJob.meta.id)
            activeJob = self:IdentifyJob(engie,self.mobileJobs)
            if activeJob then
                activeJob.meta.activeCount = activeJob.meta.activeCount + 1
            end
        end
        engie.CustomData.engieAssigned = false
    end,

    RunFactoryJobThread = function(self,job,fac)
        -- TODO: Support assistance
        local activeJob = job
        while activeJob do
            --job.meta.assigned[table.getn(job.meta.assigned)+1] = fac
            local unitID = Translation[activeJob.job.work][fac.factionCategory]
            -- Build the thing
            TroopFunctions.FactoryBuildUnit(fac,unitID)
            -- Return fac back to the pool
            self:OnCompleteFactory(activeJob.meta.id)
            activeJob = self:IdentifyJob(fac,self.mobileJobs)
            if activeJob then
                activeJob.meta.activeCount = activeJob.meta.activeCount + 1
            end
        end
        fac.CustomData.facAssigned = false
    end,

    EngineerManagementThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Assigning Engineers...")
            self:AssignEngineers(self.brain:GetEngineers())
            --self:LogJobs()
            WaitSeconds(3)
        end
    end,

    FactoryManagementThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Assigning Engineers...")
            self:AssignFactories(self.brain:GetFactories())
            --self:LogJobs()
            WaitSeconds(3)
        end
    end,

    Run = function(self)
        self:ForkThread(self.EngineerManagementThread)
        self:ForkThread(self.FactoryManagementThread)
    end,

    LogJobs = function(self)
        LOG("===== LOGGING BASECONTROLLER JOBS =====")
        LOG("MOBILE:")
        for k, v in self.mobileJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.work)..", "..tostring(v.job.priority)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.buildOrder)..", "..tostring(v.job.count)..", "..tostring(v.job.duplicates)..", "..tostring(v.meta.id))
        end
        LOG("FACTORY:")
        for k, v in self.factoryJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.work)..", "..tostring(v.job.priority)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.buildOrder)..", "..tostring(v.job.count)..", "..tostring(v.job.duplicates)..", "..tostring(v.meta.id))
        end
        LOG("===== END LOG =====")
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

function CreateBaseController(brain)
    local bc = BaseController()
    bc:Initialise(brain)
    return bc
end