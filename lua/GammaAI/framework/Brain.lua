local CreateCommandInterface = import('/mods/DilliDalli/lua/GammaAI/framework/CommandInterface.lua').CreateCommandInterface
local JobDistributor = import('/mods/DilliDalli/lua/GammaAI/framework/jobs/JobDistribution.lua').JobDistributor
local Monitoring = import('/mods/DilliDalli/lua/GammaAI/framework/Monitoring.lua')
local LocationManager = import('/mods/DilliDalli/lua/GammaAI/framework/jobs/Location.lua').LocationManager
local EconomyManager = import('/mods/DilliDalli/lua/GammaAI/framework/economy/EconomyManager.lua').EconomyManager
local PickBuildOrder = import('/mods/DilliDalli/lua/GammaAI/framework/BuildOrder.lua').PickBuildOrder

local MAP = import('/mods/DilliDalli/lua/GammaAI/framework/mapping/Mapping.lua').GetMap()

Brain = Class({
    Init = function(self,aiBrain)
        LOG("DilliDalli Brain created...")
        self.aiBrain = aiBrain
        -- For putting threads in
        self.trash = TrashBag()

        -- Strategy state
        self.strategies = {}
        self.totalWeight = 1

        -- Create brain components
        self:CreateComponents()

        -- Start a new thread to handle in-game behaviour, so this thread can return.
        self:ForkThread(self, self.GameStartThread)
    end,

    CreateComponents = function(self)
        -- For identifying units as they are built / donated
        self.monitoring = Monitoring.UnitMonitoring()
        -- For monitoring and executing all commands going from the AI to the Sim
        self.commandInterface = CreateCommandInterface()
        -- For handling job Location instances
        self.locationManager = LocationManager()
        -- For distributing jobs
        self.jobDistributor = JobDistributor()
        -- For handling mass/energy
        self.economy = EconomyManager()
    end,

    InitialiseComponents = function(self)
        self.zoneSet = MAP:GetZoneSet('ExampleZoneSet',1)

        self.monitoring:Init(self)
        self.locationManager:Init(self)
        self.jobDistributor:Init(self)
        _ALERT("GammaAI Brain initialised...")

        self.economy:Init(self)
    end,

    GameStartThread = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(1)
        -- Initialise brain components
        self:InitialiseComponents()
        -- Do any pre-building setup
        self.monitoring:Run()
        self.locationManager:Run()
        self.economy:Run()
        local buildOrder = PickBuildOrder(self)
        buildOrder:Init(self)
        WaitSeconds(4)
        -- Start the game!
        self.jobDistributor:Run()
        buildOrder:Run()
        self:ForkThread(self, self.StrategyExecutionThread)
        self:ForkThread(self, self.StrategySettingThread)
        _ALERT("GammaAI Brain running...")
    end,

    SetStrategies = function(self, strategies)
        self.strategies = {}
        self.totalWeight = 0
        for _, item in strategies do
            -- Each item has a name, weight, and a strategy instance
            self.totalWeight = self.totalWeight + math.max(item.weight,0)
            table.insert(self.strategies, item)
        end
        if self.totalWeight == 0 then
            self.totalWeight = 1
        end
    end,

    StrategySettingThread = function(self)
        -- Override this in custom AI brains to drive different behaviours
        self:SetStrategies({
            {name="Economy", weight=1, strategy=self.economy}
        })
    end,

    StrategyExecutionThread = function(self)
        -- Handle setting of budgets in accordance with the chosen strategies
        local workLimiter = CreateWorkLimiter(WORK_RATE,"Brain:StrategyExecutionThread")
        while self.brain:IsAlive() do
            local currentMassIncome = self.monitoring:GetMassIncome()
            for _, item in self.strategies do
                item.strategy:SetBudget(item.weight*currentMassIncome/self.totalWeight)
            end
            workLimiter:WaitTicks(20)
        end
    end,

    IsAlive = function(self)
        return not self.aiBrain:IsDefeated()
    end,

    ForkThread = function(self, obj, fn, ...)
        -- TODO: track number of active threads at any one time. lua_status??
        if fn and obj then
            local thread = ForkThread(fn, obj, unpack(arg))
            self.trash:Add(thread)
            return thread
        else
            WARN("ForkThread called, but provided object or function were nil...")
            return nil
        end
    end,
})

function CreateBrain(aiBrain)
    local b = Brain()
    b:Init(aiBrain)
    return b
end