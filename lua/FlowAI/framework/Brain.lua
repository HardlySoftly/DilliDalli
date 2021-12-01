local BuildDeconfliction = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').BuildDeconfliction
local MarkerManager = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').MarkerManager
local CommandInterface = import('/mods/DilliDalli/lua/FlowAI/framework/CommandInterface.lua').CommandInterface
local JobDistributor = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobDistribution.lua').JobDistributor
local Job = import('/mods/DilliDalli/lua/FlowAI/framework/production/JobDistribution.lua').Job

Brain = Class({
    Init = function(self,aiBrain)
        self.aiBrain = aiBrain
        -- For putting threads in
        self.trash = TrashBag()
        -- For preventing overlapping new building placements
        self.deconfliction = BuildDeconfliction()
        self.deconfliction:Init()
        -- For managing building on markers (i.e. mexes, hydros)
        self.markerManager = MarkerManager()
        -- For monitoring and executing all commands going from the AI to the Sim
        self.commandInterface = CommandInterface()
        -- For distributing jobs TODO: map support
        self.jobDistributor = JobDistributor()
        self.jobDistributor:Init(self,nil)
        -- Now to start up the AI
        self:ForkThread(self.Initialise)
    end,

    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(5)
        -- Some setup...
        self.markerManager:Init(self)

        local mexJob = Job()
        mexJob:Init({targetSpend = 30, count = 20, duplicates = 100000, unitBlueprintID = 'uab1103', prioritySwitch = true, markerType = 'Mass', assist = false})
        local pgenJob = Job()
        pgenJob:Init({targetSpend = 30, count = 30, duplicates = 100000, unitBlueprintID = 'uab1101'})
        local factoryJob = Job()
        factoryJob:Init({targetSpend = 30, count = 8, duplicates = 100000, unitBlueprintID = 'uab0101'})
        local tankJob = Job()
        tankJob:Init({targetSpend = 1000, count = 100, duplicates = 100000, unitBlueprintID = 'ual0201'})
        local upgradeJob = Job()
        upgradeJob:Init({targetSpend = 15, count = 1, duplicates = 1, unitBlueprintID = 'uab0201'})
        self.jobDistributor:AddMobileJob(mexJob)
        self.jobDistributor:AddMobileJob(pgenJob)
        self.jobDistributor:AddMobileJob(factoryJob)
        self.jobDistributor:AddFactoryJob(tankJob)
        self.jobDistributor:AddUpgradeJob(upgradeJob)
        self.jobDistributor:Run()
        LOG("DilliDalli Brain ready...")
    end,

    IsAlive = function(self)
        return self.aiBrain.Result ~= "defeat"
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
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