local TroopFunctions = import('/mods/DilliDalli/lua/AI/DilliDalli/TroopFunctions.lua')
local Translation = import('/mods/DilliDalli/lua/AI/DilliDalli/FactionCompatibility.lua').translate
local CreatePriorityQueue = import('/mods/DilliDalli/lua/AI/DilliDalli/PriorityQueue.lua').CreatePriorityQueue
local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local MAP = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').GetMap()

BaseController = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.jobID = 1
        self.mobileJobs = {}
        self.factoryJobs = {}
        self.upgradeJobs = {}
        self.pendingStructures = { }
        self.isBOComplete = false
        self.tID = 1
        self.assistRadius = 40
    end,

    GetThreadID = function(self)
        self.tID = self.tID + 1
        return self.tID
    end,

    CreateGenericJob = function(self,config)
        local job = {
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
            -- Feedback to the job creator on how much is being spent on this job.
            actualSpend = 0,
            -- Should other units assist this job?
            assist = true,
        }
        if config then
            for k, v in config do
                job[k] = v
            end
        end
        return job
    end,

    AddMobileJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, spend = 0, id = self.jobID, activeCount = 0, failures = 0, type="mobile" }
        self.jobID = self.jobID + 1
        table.insert(self.mobileJobs, { job = job, meta=meta })
        return meta
    end,
    AddFactoryJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, spend = 0, id = self.jobID, activeCount = 0, failures = 0, type="factory" }
        self.jobID = self.jobID + 1
        table.insert(self.factoryJobs, { job = job, meta=meta })
        return meta
    end,
    AddUpgradeJob = function(self,job)
        local meta = { assigned = {}, assisting = {}, spend = 0, id = self.jobID, activeCount = 0, failures = 0, type="upgrade" }
        self.jobID = self.jobID + 1
        table.insert(self.upgradeJobs, { job = job, meta=meta })
        return meta
    end,

    OnCompleteAssist = function(self,jobID,buildRate,thread)
        for _, job in self.mobileJobs do
            if job.meta.id == jobID then
                local index = 0
                for k, v in job.meta.assisting do
                    if v.myThread == thread then
                        job.meta.spend = job.meta.spend - buildRate*v.bp.Economy.BuildCostMass/v.bp.Economy.BuildTime
                        index = k
                    end
                end
                if not (index == 0) then
                    table.remove(job.meta.assisting,index)
                else
                    WARN("BaseController: Unable to complete assist! (mobile) "..tostring(thread)..", "..tostring(jobID))
                    self:LogJobs()
                end
                return nil
            end
        end
        for _, job in self.factoryJobs do
            if job.meta.id == jobID then
                local index
                for k, v in job.meta.assisting do
                    if v.myThread == thread then
                        job.meta.spend = job.meta.spend - buildRate*v.bp.Economy.BuildCostMass/v.bp.Economy.BuildTime
                        index = k
                    end
                end
                if index then
                    table.remove(job.meta.assisting,index)
                else
                    WARN("BaseController: Unable to complete assist! (factory) "..tostring(thread)..", "..tostring(jobID))
                    self:LogJobs()
                end
                return nil
            end
        end
        -- Arriving here may be fine, the job could already have been deleted (in which case maintaining state isn't necessary)
        return nil
    end,
    OnCompleteJob = function(self,unit,jobID,failed,buildRate,threadID,jobs)
        -- Delete a job
        -- TODO: end reliance on unit pointer for faction category (may be nil?)
        local index = 0
        for i, job in jobs do
            if job.meta.id == jobID then
                -- Keep this index
                index = i
                -- Keep track of job failures
                if failed then
                    job.meta.failures =job.meta.failures+1
                else
                    job.meta.failures = math.max(job.meta.failures-10,0)
                end
                -- Tidy up state
                job.job.count = job.job.count - 1
                local tBP = GetUnitBlueprintByName(Translation[job.job.work][unit.factionCategory])
                job.meta.spend = job.meta.spend - buildRate*tBP.Economy.BuildCostMass/tBP.Economy.BuildTime
                job.meta.activeCount = job.meta.activeCount - 1
                -- Remove from assigned workers
                local assignedIndex = 0
                for k, v in job.meta.assigned do
                    if v.thread == threadID then
                        assignedIndex = k
                    end
                end
                if assignedIndex == 0 then
                    WARN("Unable to unassign job! "..tostring(jobID)..", "..tostring(threadID))
                else
                    table.remove(job.meta.assigned,assignedIndex)
                end
                -- Complete assisting engies
                for k, v in job.meta.assisting do
                    if v.thread == threadID then
                        if v.unit and not v.unit.Dead then
                            v.unit.CustomData.assistComplete = true
                        end
                    end
                end
            end
        end
        if index ~= 0 and (not jobs[index].job.keep) and jobs[index].meta.activeCount <= 0 and jobs[index].job.count <= 0 then
            table.remove(jobs,index)
        elseif index and jobs[index].meta.failures >= 10 then
            -- Some kind of issue with this job, so stop assigning it.
            if jobs[index].job.keep then
                WARN("BaseController: Repeated Job failure, de-prioritising: "..tostring(jobs[index].job.work))
                jobs[index].job.priority = -1
                jobs[index].job.failed = true
            else
                WARN("BaseController: Repeated Job failure, removing: "..tostring(jobs[index].job.work))
                table.remove(jobs,index)
            end
        elseif not index then
            WARN("BaseController: Unable to complete job!")
        end
    end,

    DoMobileAssist = function(self,engie,job,assist,thread)
        -- Update job metadata to reflect this engie assisting the given job+target
        local buildRate = engie:GetBuildRate()
        for _, v in job.meta.assigned do
            if v.thread == assist.thread then
                job.meta.spend = job.meta.spend + buildRate*v.bp.Economy.BuildCostMass/v.bp.Economy.BuildTime
                -- Set a flag to tell everyone this engie is busy
                if not engie.CustomData then
                    engie.CustomData = {}
                end
                engie.CustomData.isAssigned = true
                table.insert(job.meta.assisting,{ unit = engie, thread = assist.thread, myThread = thread, bp = v.bp })
                return buildRate
            end
        end
        WARN("BaseController: Unable to find assist target!")
        return nil
    end,
    DoJobAssignment = function(self,unit,job,threadID)
        -- Update job metadata to reflect this unit being assigned to the given job
        local tBP = GetUnitBlueprintByName(Translation[job.job.work][unit.factionCategory])
        local buildRate = unit:GetBuildRate()
        job.meta.spend = job.meta.spend + buildRate*tBP.Economy.BuildCostMass/tBP.Economy.BuildTime
        job.meta.activeCount = job.meta.activeCount + 1
        -- Set a flag to tell everyone this unit is busy
        if not unit.CustomData then
            unit.CustomData = {}
        end
        unit.CustomData.isAssigned = true
        --LOG("Assigning: "..tostring(unit.Dead)..", "..tostring(job.meta.id)..", "..tostring(threadID))
        table.insert(job.meta.assigned,{ unit = unit, thread = threadID, bp = tBP })
        return buildRate
    end,

    RunMobileJobThread = function(self,job,engie,assist,buildRate,threadID)
        -- TODO: Support assistance
        local start = PROFILER:Now()
        local activeJob = job
        local assistData = assist
        local success = false
        while activeJob do
            if assistData then
                PROFILER:Add("RunMobileJobThread",PROFILER:Now()-start)
                TroopFunctions.EngineerAssist(engie,assistData.unit)
                start = PROFILER:Now()
                self:OnCompleteAssist(activeJob.meta.id,buildRate,threadID)
                success = true
            else
                local unitID = Translation[activeJob.job.work][engie.factionCategory]
                -- Build the thing
                PROFILER:Add("RunMobileJobThread",PROFILER:Now()-start)
                if activeJob.job.work == "MexT1" or activeJob.job.work == "MexT2" or activeJob.job.work == "MexT3" then
                    success = TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Mass")
                elseif activeJob.job.work == "Hydro" then
                    success = TroopFunctions.EngineerBuildMarkedStructure(self.brain,engie,unitID,"Hydrocarbon")
                else
                    success = TroopFunctions.EngineerBuildStructure(self.brain,engie,unitID)
                end
                start = PROFILER:Now()
                -- Return engie back to the pool
                self:OnCompleteJob(engie,activeJob.meta.id,not success,buildRate,threadID,self.mobileJobs)
            end
            if success and engie and (not engie.Dead) and (not engie.CustomData.excludeAssignment) then
                activeJob = self:IdentifyJob(engie,self.mobileJobs)
                if activeJob then
                    assistData = self:FindAssistInRadius(engie,activeJob,self.assistRadius)
                    if assistData then
                        self:DoMobileAssist(engie,activeJob,assistData,threadID)
                    else
                        self:DoJobAssignment(engie,activeJob,threadID)
                    end
                end
            else
                activeJob = nil
            end
        end
        if engie and not engie.Dead then
            engie.CustomData.isAssigned = false
        end
        PROFILER:Add("RunMobileJobThread",PROFILER:Now()-start)
    end,
    RunFactoryJobThread = function(self,job,fac,buildRate,threadID)
        -- TODO: Support assistance
        local start = PROFILER:Now()
        local activeJob = job
        while activeJob do
            local unitID = Translation[activeJob.job.work][fac.factionCategory]
            -- Build the thing
            PROFILER:Add("RunFactoryJobThread",PROFILER:Now()-start)
            TroopFunctions.FactoryBuildUnit(fac,unitID)
            start = PROFILER:Now()
            -- Return fac back to the pool
            self:OnCompleteJob(fac,activeJob.meta.id,false,buildRate,threadID,self.factoryJobs)
            if fac and (not fac.Dead) and (not fac.CustomData.excludeAssignment) then
                activeJob = self:IdentifyJob(fac,self.factoryJobs)
                if activeJob then
                    self:DoJobAssignment(fac,activeJob,threadID)
                end
            else
                activeJob = nil
            end
        end
        if fac and (not fac.Dead) then
            fac.CustomData.isAssigned = false
        end
        PROFILER:Add("RunFactoryJobThread",PROFILER:Now()-start)
    end,
    RunUpgradeJobThread = function(self,job,unit,buildRate,threadID)
        local start = PROFILER:Now()
        -- while assigned wait
        while unit and (not unit.Dead) and unit.CustomData.isAssigned do
            -- Probs fine, number of upgrades at any one time will be "smallish".  Will profile this to be sure
            PROFILER:Add("RunUpgradeJobThread",PROFILER:Now()-start)
            WaitTicks(1)
            start = PROFILER:Now()
        end
        if unit and (not unit.Dead) then
            -- Issue upgrade
            --LOG("Issuing upgrade")
            IssueClearCommands({unit})
            IssueUpgrade({unit},Translation[job.job.work][unit.factionCategory])
        end
        PROFILER:Add("RunUpgradeJobThread",PROFILER:Now()-start)
        WaitTicks(2)
        start = PROFILER:Now()
        while unit and (not unit.Dead) and (not unit:IsIdleState()) do
            -- Still probably fine
            PROFILER:Add("RunUpgradeJobThread",PROFILER:Now()-start)
            WaitTicks(2)
            start = PROFILER:Now()
        end
        -- reset exclusion flag, to release the unit for jobs
        if unit and (not unit.Dead) then
            unit.CustomData.excludeAssignment = nil
        end
        self:OnCompleteJob(unit,job.meta.id,false,buildRate,threadID,self.upgradeJobs)
        PROFILER:Add("RunUpgradeJobThread",PROFILER:Now()-start)
    end,

    AssignJobMobile = function(self,engie,job)
        local threadID = self:GetThreadID()
        -- TODO: check for unfinished buildings/exps in the same category that could be continued
        -- This must be done before we fork, or we risk over-assigning units to this job
        local assist = self:FindAssistInRadius(engie,job,self.assistRadius)
        local buildRate = 0
        if assist then
            buildRate = self:DoMobileAssist(engie,job,assist,threadID)
        else
            buildRate = self:DoJobAssignment(engie,job,threadID)
        end
        self:ForkThread(self.RunMobileJobThread,job,engie,assist,buildRate,threadID)
    end,
    AssignJobFactory = function(self,fac,job)
        local threadID = self:GetThreadID()
        -- This must be done before we fork, or we risk over-assigning units to this job
        local buildRate = self:DoJobAssignment(fac,job,threadID)
        self:ForkThread(self.RunFactoryJobThread,job,fac,buildRate,threadID)
    end,
    AssignUpgradeJob = function(self,unit,job)
        local threadID = self:GetThreadID()
        -- I can't use the regular job assignment, since units are passed in here that may already be on jobs.
        local tBP = GetUnitBlueprintByName(Translation[job.job.work][unit.factionCategory])
        local buildRate = unit:GetBuildRate()
        job.meta.spend = job.meta.spend + buildRate*tBP.Economy.BuildCostMass/tBP.Economy.BuildTime
        job.meta.activeCount = job.meta.activeCount + 1
        -- Exclude this unit from additional jobs, so we can reserve it for an upgrade.  Pertinent for factories.
        if not unit.CustomData then
            unit.CustomData = {}
        end
        unit.CustomData.excludeAssignment = true
        table.insert(job.meta.assigned,{ unit = unit, thread = threadID, bp = tBP })
        self:ForkThread(self.RunUpgradeJobThread,job,unit,buildRate,threadID)
    end,

    FindAssistInRadius = function(self,engie,job,radius)
        if not job.job.assist or not job.meta.assigned then
            return nil
        end
        local best
        local myPos = engie:GetPosition()
        for _, v in job.meta.assigned do
            local theirPos = v.unit:GetPosition()
            if MAP:CanPathTo(myPos,theirPos,"surf") and VDist3(myPos,theirPos) < self.assistRadius and not v.unit:IsBeingBuilt() then
                return { unit = v.unit, thread = v.thread }
            end
        end
        return nil
    end,
    CanDoJob = function(self,unit,job)
        -- Used for both Engineers and Factories
        -- Check if there is an available and pathable resource marker for restrictive thingies
        if (job.job.work == "MexT1" or job.job.work == "MexT2" or job.job.work == "MexT3") then
            if not self.brain.intel:EmptyMassMarkerExists(unit:GetPosition()) then
                return false
            elseif (not EntityCategoryContains(categories.TECH1,unit)) and self.isBOComplete then
                return false
            end
        elseif job.job.work == "Hydro" then
            if not self.brain.intel:FindNearestEmptyMarker(unit:GetPosition(),"Hydrocarbon") then
                return false
            elseif (not EntityCategoryContains(categories.TECH1,unit)) and self.isBOComplete then
                return false
            end
            -- TODO
            return false
        end
        if job.job.priority <= 0 or job.job.count <= 0 or job.job.targetSpend < 0 then
            return false
        end
        if job.job.com and not EntityCategoryContains(categories.COMMAND,unit) then
            -- We're still allowed to assist, just not start it
            return job.meta.spend < job.job.targetSpend and job.job.assist and self:FindAssistInRadius(unit,job,self.assistRadius)
        end
        -- TODO: Add location checks in here
        -- TODO: check for unfinished buildings/exps in the same category that could be continued
        return (
            job.meta.spend < job.job.targetSpend and (
                (
                    job.meta.activeCount < job.job.duplicates
                    and job.meta.activeCount < job.job.count
                    and unit:CanBuild(Translation[job.job.work][unit.factionCategory])
                ) or (
                    job.job.assist and self:FindAssistInRadius(unit,job,self.assistRadius)
                )
            )
        )
    end,
    CheckPriority = function(self, currentJob, newJob)
        -- Return true if the new job should be higher priority than the old job.
        -- Check the old one is actually set yet
        if not currentJob then
            return newJob.job.priority > 0
        end
        -- Check if one is a build order, in which case prioritise it.
        if currentJob.job.buildOrder and not newJob.job.buildOrder then
            return false
        elseif newJob.job.buildOrder and not currentJob.job.buildOrder then
            return true
        end
        -- Check if one has a higher priority field
        if currentJob.job.priority > newJob.job.priority then
            return false
        elseif currentJob.job.priority < newJob.job.priority then
            return true
        end
        -- Get most limiting marginal utility between each of the three restrictions on jobs: duplicates vs active, count vs active, targetSpend vs spend
        -- Division is ok because we check in CanDoJob that each denominator is strictly positive
        local oldMarginalUtility = math.max(currentJob.meta.activeCount/currentJob.job.duplicates,
                                            currentJob.meta.activeCount/currentJob.job.count,
                                            currentJob.meta.spend/currentJob.job.targetSpend)
        local newMarginalUtility = math.max(newJob.meta.activeCount/newJob.job.duplicates,
                                            newJob.meta.activeCount/newJob.job.count,
                                            newJob.meta.spend/newJob.job.targetSpend)
        return oldMarginalUtility > newMarginalUtility
    end,
    IdentifyJob = function(self,unit,jobs)
        -- TODO: Add factory assistance support
        local bestJob
        for _, job in jobs do
            -- TODO: Support assitance
            -- TODO: Support location constraints
            if self:CanDoJob(unit,job) and self:CheckPriority(bestJob,job) then
                bestJob = job
            end
        end
        return bestJob
    end,

    AssignEngineers = function(self,allEngies)
        -- TODO: implement full stable matching algorithm
        -- TODO: implement job queues (take eta into account when considering location specific jobs)
        local idle = 0
        for i=1,table.getn(allEngies) do
            local job = self:IdentifyJob(allEngies[i],self.mobileJobs)
            if job then
                self:AssignJobMobile(allEngies[i],job)
            else
                idle = idle + 1
            end
        end
        return idle
    end,
    AssignFactories = function(self,allFacs)
        -- TODO: implement full stable matching algorithm
        for i=1,table.getn(allFacs) do
            local job = self:IdentifyJob(allFacs[i],self.factoryJobs)
            if job then
                self:AssignJobFactory(allFacs[i],job)
            end
        end
    end,
    AssignUpgrades = function(self)
        -- TODO: fix location thingy
        local myPos = self.brain.intel.allies[1]
        for _, job in self.upgradeJobs do
            local units
            -- Get the right kind of units for upgrading
            if job.job.targetSpend <= 0 or job.job.count <= 0 or job.job.duplicates <= 0 then
                continue
            elseif job.job.work == "MexT2" or job.job.work == "MexT3" then
                units = self.brain.aiBrain:GetListOfUnits(categories.MASSEXTRACTION*categories.STRUCTURE,false,true)
            elseif job.job.work == "LandHQT2" or job.job.work == "LandHQT3" or job.job.work == "LandSupportT2" or job.job.work == "LandSupportT3" then
                units = self.brain.aiBrain:GetListOfUnits(categories.LAND*categories.FACTORY*categories.STRUCTURE,false,true)
            elseif job.job.work == "AirHQT2" or job.job.work == "AirHQT3" or job.job.work == "AirSupportT2" or job.job.work == "AirSupportT3" then
                units = self.brain.aiBrain:GetListOfUnits(categories.AIR*categories.FACTORY*categories.STRUCTURE,false,true)
            end
            local prioritisedUnits = CreatePriorityQueue()
            for _, unit in units do
                if (not unit) or unit.Dead or (not unit:CanBuild(Translation[job.job.work][unit.factionCategory])) or unit.CustomData.excludeAssignment or unit:IsBeingBuilt() then
                    -- Can't upgrade to the relevant unit
                    continue
                else
                    prioritisedUnits:Queue({ unit = unit, priority = VDist3(unit:GetPosition(),myPos) })
                end
            end
            while job.meta.spend < job.job.targetSpend and job.meta.activeCount < job.job.duplicates and job.meta.activeCount < job.job.count and prioritisedUnits:Size() > 0 do
                self:AssignUpgradeJob(prioritisedUnits:Dequeue().unit,job)
            end
        end
    end,

    GetEngineers = function(self)
        local units = self.brain.aiBrain:GetListOfUnits(categories.MOBILE*categories.ENGINEER,false,true)
        local n = 0
        local engies = {}
        for _, v in units do
            if (not v.CustomData or ((not v.CustomData.excludeAssignment) and (not v.CustomData.isAssigned))) and (not v:IsBeingBuilt()) and (not v.Dead) then
                table.insert(engies,v)
            end
        end
        return engies
    end,
    GetFactories = function(self)
        local units = self.brain.aiBrain:GetListOfUnits(categories.STRUCTURE*categories.FACTORY,false,true)
        local n = 0
        local facs = {}
        for _, v in units do
            if ((not v.CustomData) or ((not v.CustomData.excludeAssignment) and (not v.CustomData.isAssigned))) and (not v.Dead)  then
                n = n+1
                facs[n] = v
            end
        end
        return facs
    end,

    EngineerManagementThread = function(self)
        local i = 0
        while self.brain:IsAlive() do
            i = i+1
            local start = PROFILER:Now()
            local idle = self:AssignEngineers(self:GetEngineers())
            PROFILER:Add("EngineerManagementThread",PROFILER:Now()-start)
            if math.mod(i,10) == 0 then
                --self:LogJobs()
            end
            WaitTicks(math.min(math.max(10,idle),100))
        end
    end,
    FactoryManagementThread = function(self)
        while self.brain:IsAlive() do
            local start = PROFILER:Now()
            self:AssignFactories(self:GetFactories())
            PROFILER:Add("FactoryManagementThread",PROFILER:Now()-start)
            WaitSeconds(1)
        end
    end,
    UpgradeManagementThread = function(self)
        while self.brain:IsAlive() do
            local start = PROFILER:Now()
            self:AssignUpgrades()
            PROFILER:Add("UpgradeManagementThread",PROFILER:Now()-start)
            WaitSeconds(3)
        end
    end,

    MonitorBOCompletion = function(self)
        local isComplete = false
        while self.brain:IsAlive() and not isComplete do
            isComplete = true
            for _, v in self.mobileJobs do
                if v.job.buildOrder then
                    isComplete = false
                end
            end
            WaitTicks(2)
        end
        LOG("Build Order Completed")
        self.isBOComplete = true
    end,

    JobMonitoring = function(self)
        while self.brain:IsAlive() do
            local numAssigned = 0
            local numAssisting = 0
            for _, v in self.mobileJobs do
                numAssigned = numAssigned + table.getn(v.meta.assigned)
                numAssisting = numAssisting + table.getn(v.meta.assisting)
            end
            for _, v in self.factoryJobs do
                numAssigned = numAssigned + table.getn(v.meta.assigned)
                numAssisting = numAssisting + table.getn(v.meta.assisting)
            end
            for _, v in self.upgradeJobs do
                numAssigned = numAssigned + table.getn(v.meta.assigned)
                numAssisting = numAssisting + table.getn(v.meta.assisting)
            end
            LOG("Assigned builders: "..tostring(numAssigned))
            LOG("Assisting builders: "..tostring(numAssisting))
            LOG("Total Jobs: "..tostring(table.getn(self.mobileJobs)+table.getn(self.factoryJobs)+table.getn(self.upgradeJobs)))
            LOG("Pending Structures: "..tostring(table.getn(self.pendingStructures)))
            WaitTicks(200)
        end
    end,

    Run = function(self)
        self:ForkThread(self.EngineerManagementThread)
        self:ForkThread(self.FactoryManagementThread)
        self:ForkThread(self.UpgradeManagementThread)
        self:ForkThread(self.MonitorBOCompletion)
        --self:ForkThread(self.JobMonitoring)
    end,

    LogAssisters = function(self,id)
        for k, v in self.mobileJobs do
            if v.meta.id == id then
                s = ""
                for _, v1 in v.meta.assisting do
                    s = s.."("..tostring(v1.thread)..","..tostring(v1.myThread)..") "
                end
                LOG(tostring(k)..") { "..s.."}")
            end
        end
    end,
    LogMobileJobs = function(self)
        LOG("===== LOGGING MOBILE JOBS =====")
        for k, v in self.mobileJobs do
            LOG(tostring(k).." {")
            LOG("\tjob:")
            for k1, v1 in v.job do
                LOG("\t\t"..tostring(k1)..":\t"..tostring(v1))
                if type(v1) == "table" then
                    for k2, v2 in v1 do
                        LOG("\t\t\t"..tostring(k2)..":\t"..tostring(v2))
                    end
                end
            end
            LOG("\tmeta:")
            for k1, v1 in v.meta do
                LOG("\t\t"..tostring(k1)..":\t"..tostring(v1))
                if type(v1) == "table" then
                    for k2, v2 in v1 do
                        LOG("\t\t\t"..tostring(k2)..":\t"..tostring(v2))
                        if type(v2) == "table" then
                            for k3, v3 in v2 do
                                LOG("\t\t\t\t"..tostring(k3)..":\t"..tostring(v3))
                            end
                        end
                    end
                end
            end
        end

    end,
    LogJobs = function(self)
        LOG("===== LOGGING BASECONTROLLER JOBS =====")
        LOG("MOBILE:")
        for k, v in self.mobileJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.work)..", "..tostring(v.meta.id)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.actualSpend)..", "..tostring(v.meta.spend)..", "..tostring(v.job.count))
        end
        LOG("FACTORY:")
        for k, v in self.factoryJobs do
            LOG("\t"..tostring(k)..":\t"..tostring(v.job.work)..", "..tostring(v.meta.id)..", "..tostring(v.job.targetSpend)..", "..tostring(v.job.actualSpend)..", "..tostring(v.meta.spend)..", "..tostring(v.job.count))
        end
        LOG("===== END LOG =====")
    end,

    BaseIssueBuildMobile = function(self, units, pos, bp, id)
        table.insert(self.pendingStructures, { pos=table.copy(pos), bp=bp, id=id })
        -- TODO: check this later
        IssueBuildMobile(units,pos,bp.BlueprintId,{})
    end,
    BaseCompleteBuildMobile = function(self, id)
        local index = 0
        for k, v in self.pendingStructures do
            if v.id == id then
                index = k
            end
        end
        if not (index == 0) then
            table.remove(self.pendingStructures,index)
        else
            WARN("BaseController: No pending structure found! ("..tostring(id)..")")
        end
    end,

    LocationIsClear = function(self, location, bp)
        -- TODO: Fix this, noticed it's not working quite right
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