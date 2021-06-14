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
        -- TODO
        -- TODO: tune up allocations based on mass storage
        -- Base allocation
        self.allocations[1].mass = self.brain.monitor.mass.income*0.3
        -- Land allocation
        self.allocations[2].mass = self.brain.monitor.mass.income*0.7
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
        self.mexJob.priority = NORMAL
        self.brain.base:AddMobileJob(self.mexJob)
        -- Pgens - controlled via target spend
        self.pgenJob = self.brain.base:CreateGenericJob()
        self.pgenJob.duplicates = 3
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
        self.mexJob.duplicates = availableMex/2
        local engiesRequired = math.min(10,availableMex/2)-self.brain.monitor.units.engies.t1
        -- Do I need more pgens?
        local pgenSpend = math.min(massRemaining,(self.brain.monitor.energy.spend*1.2 - self.brain.monitor.energy.income)/8)
        self.pgenJob.targetSpend = pgenSpend
        massRemaining = massRemaining - pgenSpend
        engiesRequired = engiesRequired + math.max(0,pgenSpend/4)
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
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        
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
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
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