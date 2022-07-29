local CommandInterface = import('/mods/DilliDalli/lua/FlowAI/framework/CommandInterface.lua').CommandInterface
local JobDistributor = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/JobDistribution.lua').JobDistributor
local Monitoring = import('/mods/DilliDalli/lua/FlowAI/framework/Monitoring.lua')
local LocationManager = import('/mods/DilliDalli/lua/FlowAI/framework/jobs/Location.lua').LocationManager


Brain = Class({
    Init = function(self,aiBrain)
        LOG("DilliDalli Brain created...")
        self.aiBrain = aiBrain
        -- For putting threads in
        self.trash = TrashBag()

        -- Create brain components
        -- For identifying units as they are built / donated
        self.monitoring = Monitoring.UnitMonitoring()
        -- For monitoring and executing all commands going from the AI to the Sim
        self.commandInterface = CommandInterface()
        -- For handling job Location instances
        self.locationManager = LocationManager()
        -- For distributing jobs
        self.jobDistributor = JobDistributor()

        -- Initialise brain components
        self.monitoring:Init(self)
        self.locationManager:Init(self)
        self.jobDistributor:Init(self)
        LOG("DilliDalli Brain initialised...")

        -- Start a new thread to handle in-game behaviour, so this thread can return.
        self:ForkThread(self, self.GameStartThread)
    end,

    GameStartThread = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(1)
        -- Do any pre-building setup
        self.monitoring:Run()
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
            return nil
        end
    end,
})

function CreateBrain(aiBrain)
    local b = Brain()
    b:Init(aiBrain)
    return b
end