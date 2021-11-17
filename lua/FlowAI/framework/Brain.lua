local BuildDeconfliction = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').BuildDeconfliction
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
        local pgenJob = Job()
        pgenJob:Init({targetSpend = 100000, count = 100000, duplicates = 100000, unitBlueprintID = 'uab1101'})
        self.jobDistributor:AddMobileJob(pgenJob)
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