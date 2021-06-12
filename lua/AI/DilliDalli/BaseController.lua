local TroopFunctions = import('/mods/DilliDalli/lua/AI/DilliDalli/TroopFunctions.lua')
local Translation = import('/mods/DilliDalli/lua/AI/DilliDalli/FactionCompatibility.lua').translate

BaseController = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.jobID = 0
        self.mobileJobs = {}
        self.factoryJobs = {}
        self.idle = {}
        self.pendingStructures = { }
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
            -- If we have to disable this job for some reason, then let the creator know (priority will get reset in this case)
            failed = false,
        }
    end,

    AddMobileJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, id=self.jobID, activeCount=0, failures = 0 }
        self.jobID = self.jobID + 1
        table.insert(self.mobileJobs, { job = job, meta=meta })
    end,
    AddFactoryJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, id=self.jobID, activeCount=0 , failures = 0}
        self.jobID = self.jobID + 1
        table.insert(self.factoryJobs, { job = job, meta=meta })
    end,

    OnCompleteMobile = function(self,jobID,failed)
        -- Delete a job
        local index
        for i, job in self.mobileJobs do
            if job.meta.id == jobID then
                job.job.count = job.job.count - 1
                job.meta.activeCount = job.meta.activeCount - 1
                -- TODO: support assisting
                if failed then
                    job.meta.failures =job.meta.failures+1
                else
                    job.meta.failures = math.max(job.meta.failures-10,0)
                end
                index = i
            end
        end
        if index and (not self.mobileJobs[index].job.keep) and self.mobileJobs[index].meta.activeCount == 0 and self.mobileJobs[index].job.count == 0 then
            table.remove(self.mobileJobs,index)
        elseif index and self.mobileJobs[index].meta.failures >= 10 then
            -- Some kind of issue with this job, so stop assigning it.
            if self.mobileJobs[index].job.keep then
                WARN("DilliDalli: Repeated Job failure, de-prioritising: "..tostring(self.mobileJobs[index].job.work))
                self.mobileJobs[index].job.priority = -1
                self.mobileJobs[index].job.failed = true
            else
                WARN("DilliDalli: Repeated Job failure, removing: "..tostring(self.mobileJobs[index].job.work))
                table.remove(self.mobileJobs,index)
            end
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

    RunMobileJobThread = function(self,job,engie,assist)
        -- TODO: Support assistance
        local activeJob = job
        while activeJob do
            --job.meta.assigned[table.getn(job.meta.assigned)+1] = engie
            local unitID = Translation[activeJob.job.work][engie.factionCategory]
            -- Build the thing
            local success
            if activeJob.job.work == "MexT1" or activeJob.job.work == "MexT2" or activeJob.job.work == "MexT3" then
                success = TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Mass")
            elseif activeJob.job.work == "Hydro" then
                success = TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Hydrocarbon")
            else
                success = TroopFunctions.EngineerBuildStructure(self.brain,engie,unitID)
            end
            -- Return engie back to the pool
            self:OnCompleteMobile(activeJob.meta.id,not success)
            if not engie.Dead then
                activeJob = self:IdentifyJob(engie,self.mobileJobs)
                if activeJob then
                    activeJob.meta.activeCount = activeJob.meta.activeCount + 1
                end
            else
                return
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
            if not fac.Dead then
                activeJob = self:IdentifyJob(fac,self.mobileJobs)
                if activeJob then
                    activeJob.meta.activeCount = activeJob.meta.activeCount + 1
                end
            else
                return
            end
        end
        fac.CustomData.facAssigned = false
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

    CanDoJob = function(self,unit,job)
        -- Used for both Engineers and Factories
        -- Check if there is an available and pathable resource marker for restrictive thingies
        if (job.job.work == "MexT1" or job.job.work == "MexT2" or job.job.work == "MexT3") then
            if not self.brain.intel:FindNearestEmptyMarker(unit:GetPosition(),"Mass") then
                return false
            end
        elseif job.job.work == "Hydro" and not self.brain.intel:FindNearestEmptyMarker(unit:GetPosition(),"Hydrocarbon") then
            return false
        end
        -- TODO: Add spending checks in here
        -- TODO: Add location checks in here
        return (
            job.meta.activeCount < job.job.duplicates
            and job.meta.activeCount < job.job.count
            and unit:CanBuild(Translation[job.job.work][unit.factionCategory])
        )
    end,
    IdentifyJob = function(self,unit,jobs)
        local bestJob
        local bestPriority = 0
        local isBOJob = false
        for i=1,table.getn(jobs) do
            local job = jobs[i]
            -- TODO: Support assitance
            -- TODO: Select between equal priority things based on current spend levels / commitment levels (spend/duplicates)
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

    GetEngineers = function(self)
        local units = self.brain.aiBrain:GetListOfUnits(categories.MOBILE*categories.ENGINEER,false,true)
        local n = 0
        local engies = {}
        for _, v in units do
            if (not v.CustomData or ((not v.CustomData.excludeEngie) and (not v.CustomData.engieAssigned))) and not v:IsBeingBuilt() then
                n = n+1
                engies[n] = v
            end
        end
        return engies
    end,
    GetFactories = function(self)
        local units = self.brain.aiBrain:GetListOfUnits(categories.STRUCTURE*categories.FACTORY,false,true)
        local n = 0
        local facs = {}
        for _, v in units do
            if not v.CustomData or ((not v.CustomData.excludeFac) and (not v.CustomData.facAssigned)) then
                n = n+1
                facs[n] = v
            end
        end
        return facs
    end,

    EngineerManagementThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Assigning Engineers...")
            self:AssignEngineers(self:GetEngineers())
            --self:LogJobs()
            WaitSeconds(3)
        end
    end,
    FactoryManagementThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Assigning Engineers...")
            self:AssignFactories(self:GetFactories())
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


    BaseIssueBuildMobile = function(self, units, pos, bp, id)
        table.insert(self.pendingStructures, { pos=table.copy(pos), bp=bp, units=table.copy(units), id=id })
        IssueBuildMobile(units,pos,bp.BlueprintId,{})
    end,

    BaseCompleteBuildMobile = function(self, id)
        for k, v in self.pendingStructures do
            if v.id == id then
                table.remove(self.pendingStructures,k)
                return
            end
        end
    end,

    LocationIsClear = function(self, location, bp)
        -- Checks if any planned buildings overlap with this building.  Return true if they do not.
        local cornerX0 = location[1]+bp.SizeX/2
        local cornerZ0 = location[3]+bp.SizeZ/2
        local cornerX1 = location[1]-bp.SizeX/2
        local cornerZ1 = location[3]-bp.SizeZ/2
        for k, v in self.pendingStructures do
            -- If overlap, return false
            if location[1] == v.pos[1] and location[3] == v.pos[3] then
                -- Location is the same, return false
                return false
            elseif cornerX0 >= v.pos[1]-v.bp.SizeX/2 and cornerX0 <= v.pos[1]+v.bp.SizeX/2 and cornerZ0 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ0 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Bottom right corner
                return false
            elseif cornerX1 >= v.pos[1]-v.bp.SizeX/2 and cornerX1 <= v.pos[1]+v.bp.SizeX/2 and cornerZ0 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ0 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Bottom left corner
                return false
            elseif cornerX0 >= v.pos[1]-v.bp.SizeX/2 and cornerX0 <= v.pos[1]+v.bp.SizeX/2 and cornerZ1 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ1 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Top right corner
                return false
            elseif cornerX1 >= v.pos[1]-v.bp.SizeX/2 and cornerX1 <= v.pos[1]+v.bp.SizeX/2 and cornerZ1 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ1 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Top left corner
                return false
            end
        end
        return true
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