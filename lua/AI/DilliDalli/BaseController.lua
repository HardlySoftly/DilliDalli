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
        }
    end,
    
    CreateMobileJob = function(self)
        local job = self:CreateGenericJob()
        job.structure = nil
        return job
    end,
    
    CreateFactoryJob = function(self)
        local job = self:CreateGenericJob()
        job.unit = nil
        return job
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
        -- Delete a job, reassign the engineers.
        local index
        for i, job in self.mobileJobs do
            if job.meta.id == jobID then
                job.job.count = job.job.count - 1
                job.meta.activeCount = job.meta.activeCount - 1
                -- TODO: support assisting
                index = i
            end
        end
        if index and self.mobileJobs[index].meta.activeCount == 0 and self.mobileJobs[index].job.count == 0 then
            table.remove(self.mobileJobs,index)
        end
    end,
    
    CanDoJob = function(self,engie,job)
        return (
            job.meta.activeCount < job.job.duplicates
            and job.meta.activeCount < job.job.count
            and engie:CanBuild(Translation[job.job.structure][engie.factionCategory])
        )
    end,
    
    AssignJobMobile = function(self,engie,job)
        job.meta.activeCount = job.meta.activeCount + 1
        -- Set a flag to tell everyone this engie is busy
        if not engie.CustomData then
            engie.CustomData = {}
        end
        engie.CustomData.engieAssigned = true
        self:ForkThread(self.RunJobThread,job,engie,false)
    end,
    
    IdentifyJobMobile = function(self,engie)
        local bestJob
        local bestPriority = 0
        local isBOJob = false
        for i=1,table.getn(self.mobileJobs) do
            local job = self.mobileJobs[i]
            -- TODO: Support assitance
            if self:CanDoJob(engie,job) and ((job.job.priority > bestPriority and isBOJob == job.job.buildOrder) or (not isBOJob and job.job.buildOrder)) then
                bestPriority = job.job.priority
                bestJob = job
                isBOJob = job.job.buildOrder
            end
        end
        return bestJob
    end,
    
    AssignEngineers = function(self,allEngies)
        for i=1,table.getn(allEngies) do
            local job = self:IdentifyJobMobile(allEngies[i])
            if job then
                self:AssignJobMobile(allEngies[i],job)
            end
        end
    end,
    
    RunJobThread = function(self,job,engie,assist)
        -- TODO: Support assistance
        local activeJob = job
        while activeJob do
            --job.meta.assigned[table.getn(job.meta.assigned)+1] = engie
            local unitID = Translation[activeJob.job.structure][engie.factionCategory]
            -- Build the thing
            if activeJob.job.structure == "MexT1" or activeJob.job.structure == "MexT2" or activeJob.job.structure == "MexT3" then
                TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Mass")
            elseif activeJob.job.structure == "Hydro" then
                TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Hydrocarbon")
            else
                TroopFunctions.EngineerBuildStructure(self.brain,engie,unitID)
            end
            -- Return engie back to the pool
            self:OnCompleteMobile(activeJob.meta.id)
            activeJob = self:IdentifyJobMobile(engie)
            if activeJob then
                activeJob.meta.activeCount = activeJob.meta.activeCount + 1
            end
        end
        engie.CustomData.engieAssigned = false
    end,
    
    EngineerManagementThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Assigning Engineers...")
            self:AssignEngineers(self.brain:GetEngineers())
            --self:LogJobs()
            WaitSeconds(3)
        end
    end,
    
    Run = function(self)
        self:ForkThread(self.EngineerManagementThread)
    end,
    
    LogJobs = function(self)
        LOG("===== LOGGING BASECONTROLLER JOBS =====")
        LOG("MOBILE:")
        for k, v in self.mobileJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.structure)..", "..tostring(v.job.priority)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.buildOrder)..", "..tostring(v.job.count)..", "..tostring(v.job.duplicates)..", "..tostring(v.meta.id))
        end
        LOG("FACTORY:")
        for k, v in self.factoryJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.unit)..", "..tostring(v.job.priority)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.buildOrder)..", "..tostring(v.job.count)..", "..tostring(v.job.duplicates)..", "..tostring(v.meta.id))
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