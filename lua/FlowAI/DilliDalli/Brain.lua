local Deconflicter = import('/mods/DilliDalli/lua/FlowAI/framework/production/Locations.lua').Deconflicter
local CommandInterface = import('/mods/DilliDalli/lua/FlowAI/framework/CommandInterface.lua').CommandInterface

Brain = Class({
    Init = function(self,aiBrain)
        self.aiBrain = aiBrain
        -- For putting threads in
        self.trash = TrashBag()
        -- For preventing overlapping new building placements
        self.deconflicter = Deconflicter()
        deconflicter:Init()
        -- For monitoring and executing all commands going from the AI to the Sim
        self.commandInterface = CommandInterface()
        -- Now to start up the AI
        self:ForkThread(self.Initialise)
    end,

    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(5)
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