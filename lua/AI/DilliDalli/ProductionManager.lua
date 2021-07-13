local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()
local MAP = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').GetMap()

LOW = 100
NORMAL = 200
HIGH = 300
CRITICAL = 400

JOB_INF = 1000000000

JobGroup = Class({
    Init = function(self)
        self.jobs = {}
    end,
    Add = function(self,job,data)
        table.insert(self.jobs,{job=job,data=data})
    end,
    GetSpend = function(self)
        local sum = 0
        for _, job in self.jobs do
            sum = sum + job.job.actualSpend
        end
        return sum
    end,
    GetTargetSpend = function(self)
        local sum = 0
        for _, job in self.jobs do
            sum = sum + job.job.targetSpend
        end
        return sum
    end,
    Reset = function(self)
        for _, job in self.jobs do
            job.job.targetSpend = 0
        end
    end,
    Allocate = function(self,cond,amount)
        local sumpriority = 0
        for _, job in self.jobs do
            if job.data[cond] > 0 then
                sumpriority = sumpriority + job.data[cond]
            end
        end
        sumpriority = math.max(sumpriority,1)
        for _,job in self.jobs do
            if job.data[cond] > 0 then
                job.job.targetSpend = job.data[cond]*amount/sumpriority
            end
        end
    end,
})

function CreateJobGroup()
    local jg = JobGroup()
    jg:Init()
    return jg
end

ProductionManager = Class({
    --[[
        Responsible for:
            Resource allocation between specialist production classes
                Manage main and subsidiary production classes
                TODO: Add support for subsidiary production classes, e.g. a separate land production manager for different islands
            Strategy coordination
            Production coordination (e.g. more energy requested for upgrades/overcharge)
    ]]

    Initialise = function(self,brain)
        self.brain = brain
        self.allocations = {
            { manager = BaseProduction(), mass = 0 },
            { manager = LandProduction(), mass = 0 },
            { manager = AirProduction(), mass = 0 },
            { manager = NavyProduction(), mass = 0 },
            { manager = TacticalProduction(), mass = 0 },
        }
        for _, v in self.allocations do
            v.manager:Initialise(self.brain,self)
        end
    end,

    Run = function(self)
        WaitSeconds(1)
        self:ForkThread(self.ManageProductionThread)
        --self:ForkThread(self.ReportSpendsThread)
    end,

    ManageProductionThread = function(self)
        local start = PROFILER:Now()
        while self.brain:IsAlive() do
            --LOG("Production Management Thread")
            self:AllocateResources()
            for _, v in self.allocations do
                --local start = PROFILER:Now()
                v.manager:ManageJobs(v.mass)
                --PROFILER:Add("Production"..v.manager.name,PROFILER:Now()-start)
            end
            PROFILER:Add("ManageProductionThread",PROFILER:Now()-start)
            WaitSeconds(1)
            start = PROFILER:Now()
        end
        PROFILER:Add("ManageProductionThread",PROFILER:Now()-start)
    end,

    ReportSpendsThread = function(self)
        while self.brain:IsAlive() do
            LOG("================================================")
            for _, v in self.allocations do
                local totalSpend = 0
                for _, j in v.manager do
                    if j.actualSpend then
                        totalSpend = totalSpend + j.actualSpend
                    end
                end
                if totalSpend > 0 then
                    LOG(v.manager.name.." allocated: "..v.mass..", spending: "..tostring(totalSpend))
                end
            end
            WaitSeconds(15)
        end
    end,

    AllocateResources = function(self)
        -- TODO: subsidiary production and proper management.  Allocations need to be strategy dependent.
        -- Tune up allocations based on mass storage (0.85 when empty, 1.8 when full)
        local storageModifier = 0.85 + 1*self.brain.aiBrain:GetEconomyStoredRatio('MASS')
        local availableMass = self.brain.monitor.mass.income*storageModifier
        local resourceSections = {5,5,20,60,JOB_INF} --Divide income into five sections- first 5 mass, next 5 mass, next 20 mass, next 60 mass, the rest
        local typeSections = {--What amount each type will spend of each of the 5 sections
            {1, 0.1, 0.1, 0.3, 0.4},--base
            {0, 0.9, 0.8, 0.65, 0.6},--land
            {0, 0, 0.1, 0.05, 0},--air
        }
        local alreadySpent = 0
        local sectionMass = {}
        for k,v in resourceSections do--Use resourceSections as a guide to divy up the income into segments
            sectionMass[k]=math.min(v,availableMass-alreadySpent)--The amount each section can take is At Most the value it has- but if we have less mass than the max, we use that instead
            alreadySpent=alreadySpent+sectionMass[k]
        end
        for k,v in typeSections do
            local sum=0
            for i,j in sectionMass do--Multiply the typeSection ratios against the income segments and then sum them to get the spend by category
                sum=sum+j*v[i]
            end
            self.allocations[k].mass=sum
        end
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

function CreateProductionManager(brain)
    local pm = ProductionManager()
    pm:Initialise(brain)
    return pm
end

BaseProduction = Class({
    --[[
        Responsible for:
            Mex construction
            Mex upgrades
            Pgen construction
            ACU defensive production, e.g. t2/3 upgrades, RAS, etc.
            Base defenses (pd, aa, torpedo launchers)
            Engineer production
            Reclaim

        Main instance will control all mex upgrades and pgen construction.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Base"
        self.brain = brain
        self.coord = coord
        -- Mex expansion, controlled via duplicates (considered to cost nothing mass wise)
        self.mexJob = self.brain.base:CreateGenericJob({ duplicates = 10, count = JOB_INF, targetSpend = JOB_INF, work = "MexT1", keep = true, priority = LOW, assist = false })
        self.brain.base:AddMobileJob(self.mexJob)
        -- Pgens - controlled via target spend
        self.t1PgenJob = self.brain.base:CreateGenericJob({ duplicates = 10, count = JOB_INF, targetSpend = 0, work = "PgenT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t1PgenJob)
        self.t2PgenJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = JOB_INF, targetSpend = 0, work = "PgenT2", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t2PgenJob)
        self.t3PgenJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "PgenT3", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t3PgenJob)
        -- Engies - controlled via job count (considered to cost nothing mass wise)
        self.t1EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1EngieJob)
        self.t2EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT2", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t2EngieJob)
        self.t3EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT3", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t3EngieJob)
        -- Mass upgrades - controlled via target spend
        self.mexT2Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MexT2", keep = true, priority = NORMAL })
        self.brain.base:AddUpgradeJob(self.mexT2Job)
        self.mexT3Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MexT3", keep = true, priority = NORMAL })
        self.brain.base:AddUpgradeJob(self.mexT3Job)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        local massRemaining = mass - self.t1EngieJob.actualSpend
        local availableMex = self.brain.intel:GetNumAvailableMassPoints()
        self.mexJob.duplicates = availableMex/2
        local engiesRequired = 1+math.min(3,math.log(availableMex+1))*math.sqrt(mass)-self.brain.monitor.units.engies.t1
        -- Drop out early if we're still doing our build order
        if not self.brain.base.isBOComplete then
            self.t1EngieJob.count = engiesRequired
            return nil
        end
        local energyModifier = 2 - 0.9*self.brain.aiBrain:GetEconomyStoredRatio('ENERGY')
        local amEmpty = self.brain.aiBrain:GetEconomyStoredRatio('ENERGY') < 0.05
        -- Do I need more pgens?
        local pgenSpend = math.max(math.min(massRemaining,(self.brain.monitor.energy.spend*energyModifier - self.brain.monitor.energy.income)/4),-1)
        if self.brain.monitor.units.engies.t3 > 0 then
            self.t1PgenJob.targetSpend = 0
            self.t2PgenJob.targetSpend = 0
            self.t3PgenJob.targetSpend = pgenSpend
        elseif self.brain.monitor.units.engies.t2 > 0 then
            self.t1PgenJob.targetSpend = 0
            self.t2PgenJob.targetSpend = pgenSpend
            self.t3PgenJob.targetSpend = 0
        else
            self.t1PgenJob.targetSpend = pgenSpend
            self.t2PgenJob.targetSpend = 0
            self.t3PgenJob.targetSpend = 0
        end
        if amEmpty then
            self.t1PgenJob.priority = CRITICAL
            self.t2PgenJob.priority = CRITICAL
            self.t3PgenJob.priority = CRITICAL
        else
            self.t1PgenJob.priority = NORMAL
            self.t2PgenJob.priority = NORMAL
            self.t3PgenJob.priority = NORMAL
        end
        massRemaining = massRemaining - pgenSpend
        -- Do I need some mex upgrades?
        --LOG("Base spend manager - spent:"..tostring(pgenSpend)..", remaining: "..tostring(massRemaining)..", allocated: "..tostring(mass))
        if massRemaining > 8 or availableMex <= 2 then
            -- TODO: use a buffer to smooth spends on mexes (don't want blips to trigger mass upgrades)
            -- TODO: Distribute mass remaining between mex upgrade jobs
            self.mexT2Job.targetSpend = massRemaining - 5
            if self.brain.monitor.units.mex.t2 > self.brain.monitor.units.mex.t1*2 then
                self.mexT2Job.targetSpend = self.mexT2Job.targetSpend * 0.6
                self.mexT3Job.targetSpend = massRemaining - self.mexT2Job.actualSpend - 10
            else
                self.mexT3Job.targetSpend = 0
            end
        else
            self.mexT2Job.targetSpend = 0
        end
        -- How many engies do I need?
        self.t1EngieJob.count = engiesRequired
        self.t2EngieJob.count = 2-self.brain.monitor.units.engies.t2-self.brain.monitor.units.engies.t3
        self.t3EngieJob.count = 2-self.brain.monitor.units.engies.t3
    end,
})

LandProduction = Class({
    --[[
        Responsible for:
            Land Factory production
            Land unit composition/production
            Land factory upgrades
            ACU offensive production, e.g. PD creeps, gun upgrades, etc.

        Main instance has exclusive control of HQ upgrades.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Land"
        self.brain = brain
        self.coord = coord
        self.island = not MAP:CanPathTo(self.brain.intel.allies[1],self.brain.intel.enemies[1],"land")
        -- Base zone
        self.baseZone = self.brain.intel:FindZone(self.brain.intel.allies[1])
        -- T1 jobs
        self.t1ScoutJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 5, work = "LandScoutT1", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t1ScoutJob)
        self.t1TankJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1TankJob)
        self.t1ArtyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "ArtyT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1ArtyJob)
        self.t1AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT1", keep = true, priority = NORMAL-1 })
        self.brain.base:AddFactoryJob(self.t1AAJob)
        self.t1Jobs = CreateJobGroup()
        self.t1Jobs:Add(self.t1TankJob,{10,8,8,5})
        self.t1Jobs:Add(self.t1ArtyJob,{0,3,2,5})
        self.t1Jobs:Add(self.t1AAJob,{})
        -- T2 jobs
        self.t2TankJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT2", keep = true, priority = NORMAL+1 })
        self.brain.base:AddFactoryJob(self.t2TankJob)
        self.t2RangedJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "RangedT2", keep = true, priority = NORMAL+1 })
        self.brain.base:AddFactoryJob(self.t2RangedJob)
        self.t2HoverJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AmphibiousT2", keep = true, priority = NORMAL+1 })
        self.brain.base:AddFactoryJob(self.t2HoverJob)
        self.t2AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t2AAJob)
        self.t2MMLJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MMLT2", keep = true, priority = NORMAL+1 })
        self.brain.base:AddFactoryJob(self.t2MMLJob)
        self.t2Jobs = CreateJobGroup()
        self.t2Jobs:Add(self.t2TankJob,{7,6})
        self.t2Jobs:Add(self.t2RangedJob,{1,2})
        self.t2Jobs:Add(self.t2HoverJob,{})
        self.t2Jobs:Add(self.t2AAJob,{2,1})
        self.t2Jobs:Add(self.t2MMLJob,{0,1})
        -- T3 jobs
        self.t3LightJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT3", keep = true, priority = NORMAL+2 })
        self.brain.base:AddFactoryJob(self.t3LightJob)
        self.t3HeavyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "HeavyLandT3", keep = true, priority = NORMAL+3 })
        self.brain.base:AddFactoryJob(self.t3HeavyJob)
        self.t3RangedJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "RangedT3", keep = true, priority = NORMAL+3 })
        self.brain.base:AddFactoryJob(self.t3RangedJob)
        self.t3AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT3", keep = true, priority = NORMAL+1 })
        self.brain.base:AddFactoryJob(self.t3AAJob)
        self.t3ArtyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "ArtyT3", keep = true, priority = NORMAL+2 })
        self.brain.base:AddFactoryJob(self.t3ArtyJob)
        self.t3Jobs = CreateJobGroup()
        self.t3Jobs:Add(self.t3LightJob,{5,0})
        self.t3Jobs:Add(self.t3HeavyJob,{2,5})
        self.t3Jobs:Add(self.t3RangedJob,{1,4})
        self.t3Jobs:Add(self.t3AAJob,{1,1})
        self.t3Jobs:Add(self.t3ArtyJob,{0,0})
        -- Experimental jobs
        self.expJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "LandExp", keep = true, priority = HIGH })
        self.brain.base:AddMobileJob(self.expJob)
        -- Factory Jobs
        self.facJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandFactoryT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.facJob)
        self.t2HQJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "LandHQT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2HQJob)
        self.t3HQJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "LandHQT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3HQJob)
        self.t2SupportJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandSupportT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2SupportJob)
        self.t3SupportJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandSupportT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3SupportJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        if self.island then
            return self:ManageIslandJobs(mass)
        end
        local massRemaining = mass
        -- Factory HQ upgrade decisions
        --    Based on:
        --        - investment in units
        --        - available mexes
        --        - available mass
        --        - existence of support factories
        self.t2HQJob.targetSpend = 0
        self.t2HQJob.count = 0
        self.t3HQJob.targetSpend = 0
        self.t3HQJob.count = 0
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- We have a t3 HQ
        elseif self.brain.monitor.units.facs.land.hq.t2 > 0 then
            -- We have only a t2 HQ
            if (self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 70) or (self.brain.monitor.units.land.mass.total > 7000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t3HQJob.count = 1
                self.t3HQJob.targetSpend = math.min(40,mass)
            end
        else
            -- We have no HQs
            -- Otherwise make a decision based on available mass/unit investment
            if (self.brain.monitor.units.facs.land.total.t2 + self.brain.monitor.units.facs.land.total.t3 > 0)
                    or (mass > 30) or (self.brain.monitor.units.land.mass.total > 3000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t2HQJob.count = 1
                self.t2HQJob.targetSpend = math.min(20,mass)
            end
        end
        -- Update remaining mass
        massRemaining = math.max(0,massRemaining - self.t2HQJob.actualSpend - self.t3HQJob.actualSpend)

        -- Factory support upgrade decisions (2)
        --    Based on:
        --        - HQ availability
        --        - Spend per factory (by tier)
        --        - investment in units
        local t1Spend = self.t1Jobs:GetSpend()
        local t2Spend = self.t2Jobs:GetSpend()
        local t2Target = self.t2Jobs:GetTargetSpend()
        local t3Spend = self.t3Jobs:GetSpend()
        local t3Target = self.t3Jobs:GetTargetSpend()
        self.facJob.targetSpend = 0
        self.t2SupportJob.targetSpend = 0
        self.t2SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t1/4,math.max(self.brain.monitor.units.facs.land.total.t2/2,self.brain.monitor.units.facs.land.total.t3))
        self.t3SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t2/4,self.brain.monitor.units.facs.land.total.t3/2)
        self.t3SupportJob.targetSpend = 0
        if (t3Spend < t3Target/1.2) and (self.brain.monitor.units.facs.land.idle.t3 == 0) then
            if self.brain.monitor.units.facs.land.total.t2 - self.brain.monitor.units.facs.land.hq.t2 > 0 then
                self.t3SupportJob.targetSpend = (t3Target - t3Spend)/2
            elseif self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = (t3Target - t3Spend)/2
            else
                self.facJob.targetSpend = t3Target - t3Spend
            end
        end
        if t2Spend < t2Target/1.2 and (self.brain.monitor.units.facs.land.idle.t2 == 0) then
            if self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = self.t2SupportJob.targetSpend + t2Target - t2Spend
            else
                self.facJob.targetSpend = self.facJob.targetSpend + t2Target - t2Spend
            end
        end
        massRemaining = math.max(0,massRemaining - self.t2SupportJob.actualSpend*2 - self.t3SupportJob.actualSpend*2 - self.facJob.actualSpend)

        -- T1,T2,T3,Exp spending allocations + ratios (1)
        --    Based on:
        --        - Available factories
        --        - Available mass
        --        - Enemy intel (TODO)
        --    Remember Hi Pri tank decisions (for early game)
        if massRemaining > 100 and self.brain.monitor.units.engies.t3 > 0 then
            -- Time for an experimental
            self.expJob.targetSpend = (massRemaining-50)*0.8
        else
            self.expJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - self.expJob.actualSpend)
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T3 spend
            self.t3Jobs:Reset()
            local actualMass = massRemaining*1.2
            if self.brain.monitor.units.land.count.t3 < 16 then
                self.t3Jobs:Allocate(1,actualMass)
            else
                self.t3Jobs:Allocate(2,actualMass)
            end
        end
        massRemaining = math.max(0,massRemaining - t3Spend)
        if self.brain.monitor.units.facs.land.hq.t2+self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T2 spend
            local actualMass = massRemaining*1.2
            self.t2Jobs:Reset()
            if self.brain.monitor.units.land.count.t2 < 20 then
                self.t2Jobs:Allocate(1,actualMass)
            else
                self.t2Jobs:Allocate(2,actualMass)
            end
        end
        massRemaining = math.max(0,massRemaining - t2Spend)
        if true then
            -- T1 spend
            local actualMass = massRemaining*1.2
            self.t1ScoutJob.count = table.getn(self.brain.army.land.groups) - self.brain.monitor.units.land.count.scout
            self.t1Jobs:Reset()
            if self.brain.monitor.units.land.count.total < 20 then
                self.t1Jobs:Allocate(1,actualMass)
            elseif self.brain.monitor.units.land.count.t2+self.brain.monitor.units.land.count.t3 < 10 then
                self.t1Jobs:Allocate(2,actualMass)
            elseif self.brain.monitor.units.land.mass.total < 5000 then
                self.t1Jobs:Allocate(3,actualMass)
            else
                self.t1Jobs:Allocate(4,actualMass)
            end
        end
        massRemaining = math.max(0,massRemaining - t1Spend)

        -- Upgrade jobs to high/critical priority if there's an urgent need for them (4)
        -- T1 tanks early game
        -- AA if being bombed
        if (self.brain.monitor.units.land.count.total < 30) and (((self.brain.monitor.units.engies.t1 - 1) * 1.5) > self.brain.monitor.units.land.count.total - self.brain.monitor.units.land.count.scout) then
            self.t1TankJob.priority = HIGH
            self.t1ArtyJob.priority = HIGH
        else
            self.t1TankJob.priority = NORMAL
            self.t1ArtyJob.priority = NORMAL
        end
        if self.baseZone.intel.threat.air.enemy < 0.5 then
            self.t3AAJob.priority = NORMAL+1
            self.t2AAJob.priority = NORMAL
            self.t1AAJob.priority = NORMAL-1
        else
            self.t3AAJob.priority = CRITICAL
            self.t3AAJob.targetSpend = math.max(10,self.t3AAJob.targetSpend)
            self.t2AAJob.priority = CRITICAL
            self.t2AAJob.targetSpend = math.max(10,self.t2AAJob.targetSpend)
            self.t1AAJob.priority = CRITICAL
            self.t1AAJob.targetSpend = math.max(10,self.t1AAJob.targetSpend)
        end

        if massRemaining > 0 and self.brain.base.isBOComplete
                             and self.brain.monitor.units.facs.land.idle.t1+self.brain.monitor.units.facs.land.idle.t2+self.brain.monitor.units.facs.land.idle.t3 == 0 then
            self.facJob.targetSpend = self.facJob.targetSpend + massRemaining
        end
    end,

    ManageIslandJobs = function(self,mass)
        local massRemaining = mass
        -- Dodgy copy paste because I have no time while writing this :)
        self.t2HQJob.targetSpend = 0
        self.t2HQJob.count = 0
        self.t3HQJob.targetSpend = 0
        self.t3HQJob.count = 0
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- We have a t3 HQ
        elseif self.brain.monitor.units.facs.land.hq.t2 > 0 then
            -- We have only a t2 HQ
            if (self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 70) or (self.brain.monitor.units.land.mass.total > 7000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t3HQJob.count = 1
                self.t3HQJob.targetSpend = math.min(40,mass)
            end
        else
            -- We have no HQs
            -- Otherwise make a decision based on available mass/unit investment
            if (self.brain.monitor.units.facs.land.total.t2 + self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 12) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t2HQJob.count = 1
                self.t2HQJob.targetSpend = math.min(20,mass)
            end
        end
        -- Update remaining mass
        massRemaining = math.max(0,massRemaining - self.t2HQJob.actualSpend - self.t3HQJob.actualSpend)

        -- Factory support upgrade decisions (2)
        --    Based on:
        --        - HQ availability
        --        - Spend per factory (by tier)
        --        - investment in units
        local t1Spend = self.t1ScoutJob.actualSpend + self.t1TankJob.actualSpend + self.t1ArtyJob.actualSpend + self.t1AAJob.actualSpend
        local t2Spend = self.t2TankJob.actualSpend + self.t2HoverJob.actualSpend + self.t2AAJob.actualSpend + self.t2MMLJob.actualSpend
        local t2Target = self.t2TankJob.targetSpend + self.t2HoverJob.targetSpend + self.t2AAJob.targetSpend + self.t2MMLJob.targetSpend
        local t3Spend = self.t3LightJob.actualSpend + self.t3HeavyJob.actualSpend + self.t3AAJob.actualSpend + self.t3ArtyJob.actualSpend
        local t3Target = self.t3LightJob.targetSpend + self.t3HeavyJob.targetSpend + self.t3AAJob.targetSpend + self.t3ArtyJob.targetSpend
        self.facJob.targetSpend = 0
        self.t2SupportJob.targetSpend = 0
        self.t2SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t1/4,math.max(self.brain.monitor.units.facs.land.total.t2/2,self.brain.monitor.units.facs.land.total.t3))
        self.t3SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t2/4,self.brain.monitor.units.facs.land.total.t3/2)
        self.t3SupportJob.targetSpend = 0
        if (t3Spend < t3Target/1.2) and (self.brain.monitor.units.facs.land.idle.t3 == 0) then
            if self.brain.monitor.units.facs.land.total.t2 - self.brain.monitor.units.facs.land.hq.t2 > 0 then
                self.t3SupportJob.targetSpend = t3Target - t3Spend
            elseif self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = t3Target - t3Spend
            else
                self.facJob.targetSpend = t3Target - t3Spend
            end
        end
        if t2Spend < t2Target/1.2 and (self.brain.monitor.units.facs.land.idle.t2 == 0) then
            if self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = self.t2SupportJob.targetSpend + t2Target - t2Spend
            else
                self.facJob.targetSpend = self.facJob.targetSpend + t2Target - t2Spend
            end
        end
        massRemaining = math.max(0,massRemaining - self.t2SupportJob.actualSpend - self.t3SupportJob.actualSpend - self.facJob.actualSpend)

        -- T1,T2,T3,Exp spending allocations + ratios (1)
        --    Based on:
        --        - Available factories
        --        - Available mass
        --        - Enemy intel (TODO)
        --    Remember Hi Pri tank decisions (for early game)
        if massRemaining > 100 and self.brain.monitor.units.engies.t3 > 0 then
            -- Time for an experimental
            self.expJob.targetSpend = (massRemaining-50)*0.8
        else
            self.expJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - self.expJob.actualSpend)
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T3 spend
            self.t3LightJob.targetSpend = 0
            self.t3HeavyJob.targetSpend = 0
            self.t3AAJob.targetSpend = 0
            self.t3ArtyJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t3Spend)
        if self.brain.monitor.units.facs.land.hq.t2+self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T2 spend
            local actualMass = massRemaining*1.2
            self.t2TankJob.targetSpend = 0
            self.t2HoverJob.targetSpend = actualMass
            self.t2AAJob.targetSpend = 0
            self.t2MMLJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t2Spend)
        if true then
            -- T1 spend
            local actualMass = massRemaining*1.2
            self.t1ScoutJob.targetSpend = 0
            self.t1TankJob.targetSpend = 0
            self.t1ArtyJob.targetSpend = 0
            self.t1AAJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t1Spend)

        -- Upgrade jobs to high/critical priority if there's an urgent need for them (4)
        -- T1 tanks early game
        -- AA if being bombed
        if self.baseZone.control.air.enemy < 0.5 then
            self.t3AAJob.priority = NORMAL
            self.t2AAJob.priority = NORMAL
            self.t1AAJob.priority = NORMAL
        else
            self.t3AAJob.priority = CRITICAL
            self.t3AAJob.targetSpend = math.max(10,self.t3AAJob.targetSpend)
            self.t2AAJob.priority = CRITICAL
            self.t2AAJob.targetSpend = math.max(10,self.t2AAJob.targetSpend)
            self.t1AAJob.priority = CRITICAL
            self.t1AAJob.targetSpend = math.max(10,self.t1AAJob.targetSpend)
        end

        if massRemaining > 0 and self.brain.base.isBOComplete
                             and self.brain.monitor.units.facs.land.idle.t1+self.brain.monitor.units.facs.land.idle.t2+self.brain.monitor.units.facs.land.idle.t3 == 0 then
            self.facJob.targetSpend = self.facJob.targetSpend + massRemaining
        end
    end,
})

AirProduction = Class({
    --[[
        Responsible for:
            Air Factory production
            Air unit composition/production
            Air factory upgrades

        Main instance has exclusive control of HQ upgrades.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Air"
        self.brain = brain
        self.coord = coord
        -- T1 units
        self.intieJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "IntieT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.intieJob)
        self.scoutJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "AirScoutT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.scoutJob)
        -- Factories
        self.facJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AirFactoryT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.facJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        self.intieJob.targetSpend = mass*1.2
        self.facJob.targetSpend = 0
        if (self.brain.monitor.units.air.count.total > 0) and (self.brain.monitor.units.air.count.scout < 0.1 + math.log(1+(self.brain.monitor.units.air.count.total))*4) then
            self.scoutJob.targetSpend = 5
        else
            self.scoutJob.targetSpend = 0
        end
        if self.brain.monitor.units.facs.air.idle.t1 == 0 and self.brain.base.isBOComplete then
            self.facJob.targetSpend = mass - self.intieJob.actualSpend - self.scoutJob.actualSpend - self.facJob.actualSpend
        end
    end,
})

NavyProduction = Class({
    --[[
        TODO
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Navy"
        self.brain = brain
        self.coord = coord
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
    end,
})

TacticalProduction = Class({
    --[[
        Responsible for:
            TML / TMD
            Nukes / AntiNuke
            Base Shielding
            T3 Artillery
            Game Enders - e.g. T3 artillery, paragon, novax, etc

        Subsidiary instances restricted to cheap stuff (tmd/tml/shields)
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Tactical"
        self.brain = brain
        self.coord = coord
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
    end,
})