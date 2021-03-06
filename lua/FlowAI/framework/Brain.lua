local CommandInterface = import('/mods/DilliDalli/lua/FlowAI/framework/CommandInterface.lua').CommandInterface
local JobDistributor = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/JobDistribution.lua').JobDistributor
local Monitoring = import('/mods/DilliDalli/lua/FlowAI/framework/Monitoring.lua')
local LocationManager = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Location.lua').LocationManager

local MAP = import('/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua').GetMap()

local MassMarkerManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/MarkerManagement.lua').MassMarkerManager
local PowerAreaManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/AreaManagement.lua').PowerAreaManager
local MassUpgradeManager = import('/mods/DilliDalli/lua/FlowAI/framework/economy/UpgradeManagement.lua').MassUpgradeManager

Brain = Class({
    Init = function(self,aiBrain)
        LOG("DilliDalli Brain created...")
        self.aiBrain = aiBrain
        -- For putting threads in
        self.trash = TrashBag()

        -- Create brain components
        self:CreateComponents()

        -- Start a new thread to handle in-game behaviour, so this thread can return.
        self:ForkThread(self, self.GameStartThread)
    end,

    CreateComponents = function(self)
        -- For identifying units as they are built / donated
        self.monitoring = Monitoring.UnitMonitoring()
        -- For monitoring and executing all commands going from the AI to the Sim
        self.commandInterface = CommandInterface()
        -- For handling job Location instances
        self.locationManager = LocationManager()
        -- For distributing jobs
        self.jobDistributor = JobDistributor()

        self.mexes = MassMarkerManager()
        self.pgens = PowerAreaManager()
        self.upgrades = MassUpgradeManager()
    end,

    InitialiseComponents = function(self)
        self.zoneSet = MAP:GetZoneSet('ExampleZoneSet',1)

        self.monitoring:Init(self)
        self.locationManager:Init(self)
        self.jobDistributor:Init(self)
        LOG("DilliDalli Brain initialised...")

        self.mexes:Init(self)
        self.mexes:SetBudget(20)
        self.pgens:Init(self,"POWER_T1")
        self.pgens:SetBudget(20)
        self.upgrades:Init(self,"MEX_T1","MEX_T2")
        self.upgrades:SetBudget(20)
    end,

    GameStartThread = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(1)
        -- Initialise brain components
        self:InitialiseComponents()
        -- Do any pre-building setup
        self.monitoring:Run()
        self.mexes:Run()
        self.pgens:Run()
        self.upgrades:Run()
        self.locationManager:Run()
        WaitSeconds(4)
        -- Start the game!
        self.jobDistributor:Run()
        LOG("DilliDalli Brain running...")
    end,

    IsAlive = function(self)
        return self.aiBrain.Result ~= "defeat"
    end,

    ForkThread = function(self, obj, fn, ...)
        if fn then
            local thread = ForkThread(fn, obj, unpack(arg))
            self.trash:Add(thread)
            return thread
        else
            WARN("ForkThread called, but provided function was nil...")
            return nil
        end
    end,
})

function CreateBrain(aiBrain)
    local b = Brain()
    b:Init(aiBrain)
    return b
end