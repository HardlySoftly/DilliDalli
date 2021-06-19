LOW = 100
NORMAL = 200
HIGH = 300
CRITICAL = 400

JOB_INF = 1000000000

ProductionManager = Class({
    --[[
        Responsible for:
            Resource allocation between specialist production classes
                Manage main and subsidiary production classes
                TODO: Add support for subsidiary production classes
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
    end,

    ManageProductionThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Production Management Thread")
            self:AllocateResources()
            for _, v in self.allocations do
                v.manager:ManageJobs(v.mass)
            end
            WaitSeconds(1)
        end
    end,

    AllocateResources = function(self)
        -- TODO: subsidiary production and proper management
        -- TODO: tune up allocations based on mass storage
        local availableMass = self.brain.monitor.mass.income
        local section0 = math.min(6,availableMass)
        local section1 = math.min(14,availableMass-section0)
        local section2 = availableMass-section0-section1
        -- Base allocation
        self.allocations[1].mass = section0 + 0.2*section1 + 0.2*section2
        -- Land allocation
        self.allocations[2].mass = section1*0.8+section2*0.7
        -- Air allocation
        self.allocations[3].mass = section2*0.1
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
        self.brain = brain
        self.coord = coord
        -- Mex expansion, controlled via duplicates (considered to cost nothing mass wise)
        self.mexJob = self.brain.base:CreateGenericJob()
        self.mexJob.duplicates = 2
        self.mexJob.count = JOB_INF
        self.mexJob.targetSpend = JOB_INF
        self.mexJob.work = "MexT1"
        self.mexJob.keep = true
        self.mexJob.priority = LOW
        self.mexJob.assist = false
        self.brain.base:AddMobileJob(self.mexJob)
        -- Pgens - controlled via target spend
        self.pgenJob = self.brain.base:CreateGenericJob()
        self.pgenJob.duplicates = 10
        self.pgenJob.count = JOB_INF
        self.pgenJob.targetSpend = 0
        self.pgenJob.work = "PgenT1"
        self.pgenJob.keep = true
        self.pgenJob.priority = NORMAL
        self.brain.base:AddMobileJob(self.pgenJob)
        -- Engies - controlled via job count (considered to cost nothing mass wise)
        self.engieJob = self.brain.base:CreateGenericJob()
        self.engieJob.duplicates = 2
        self.engieJob.count = 0
        self.engieJob.targetSpend = JOB_INF
        self.engieJob.work = "EngineerT1"
        self.engieJob.keep = true
        self.engieJob.priority = NORMAL
        self.brain.base:AddFactoryJob(self.engieJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        local massRemaining = mass
        local availableMex = self.brain.intel:GetNumAvailableMassPoints()
        self.mexJob.duplicates = math.min(availableMex/2,math.max(self.brain.monitor.units.engies.t1-4,self.brain.monitor.units.engies.t1/1.5))
        local engiesRequired = 4+math.min(10,availableMex/2)-self.brain.monitor.units.engies.t1
        -- Drop out early if we're still doing our build order
        if not self.brain.base.isBOComplete then
            self.engieJob.count = engiesRequired
            return nil
        end
        -- Do I need more pgens?
        local pgenSpend = math.min(massRemaining,(self.brain.monitor.energy.spend*1.2 - self.brain.monitor.energy.income)/4)
        --LOG("Pgen stats: "..tostring(pgenSpend)..": "..tostring(self.brain.monitor.energy.spend)..", "..tostring(self.brain.monitor.energy.income)..", "..tostring(self.pgenJob.actualSpend))
        self.pgenJob.targetSpend = pgenSpend
        massRemaining = massRemaining - pgenSpend
        engiesRequired = engiesRequired + math.max(0,pgenSpend/3)
        -- Do I need some mex upgrades?
        -- TODO: this.
        -- How many engies do I need?
        self.engieJob.count = engiesRequired
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
        self.brain = brain
        self.coord = coord
        self.tankJob = self.brain.base:CreateGenericJob()
        self.tankJob.duplicates = JOB_INF
        self.tankJob.count = JOB_INF
        self.tankJob.targetSpend = 0
        self.tankJob.work = "DirectFireT1"
        self.tankJob.keep = true
        self.tankJob.priority = NORMAL
        self.brain.base:AddFactoryJob(self.tankJob)
        self.facJob = self.brain.base:CreateGenericJob()
        self.facJob.duplicates = JOB_INF
        self.facJob.count = JOB_INF
        self.facJob.targetSpend = 0
        self.facJob.work = "LandFactoryT1"
        self.facJob.keep = true
        self.facJob.priority = NORMAL
        self.brain.base:AddMobileJob(self.facJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        self.tankJob.targetSpend = mass*1.2
        self.facJob.targetSpend = 0
        if self.brain.monitor.units.facs.land.idle.t1 == 0 and self.brain.base.isBOComplete then
            self.facJob.targetSpend = mass - self.tankJob.actualSpend
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
        self.brain = brain
        self.coord = coord
        self.intieJob = self.brain.base:CreateGenericJob()
        self.intieJob.duplicates = JOB_INF
        self.intieJob.count = JOB_INF
        self.intieJob.targetSpend = 0
        self.intieJob.work = "IntieT1"
        self.intieJob.keep = true
        self.intieJob.priority = NORMAL
        self.brain.base:AddFactoryJob(self.intieJob)
        self.facJob = self.brain.base:CreateGenericJob()
        self.facJob.duplicates = JOB_INF
        self.facJob.count = JOB_INF
        self.facJob.targetSpend = 0
        self.facJob.work = "AirFactoryT1"
        self.facJob.keep = true
        self.facJob.priority = NORMAL
        self.brain.base:AddMobileJob(self.facJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        self.intieJob.targetSpend = mass*1.2
        self.facJob.targetSpend = 0
        if self.brain.monitor.units.facs.air.idle.t1 == 0 and self.brain.base.isBOComplete then
            self.facJob.targetSpend = mass - self.intieJob.actualSpend
        end
    end,
})

NavyProduction = Class({
    --[[
        TODO
    ]]

    Initialise = function(self,brain,coord)
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
        self.brain = brain
        self.coord = coord
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
    end,
})