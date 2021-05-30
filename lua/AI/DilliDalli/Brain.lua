Brain = Class({
    OnCreate = function(self,aiBrain)
        self.aiBrain = aiBrain
        self.Trash = TrashBag()
        self:ForkThread(self.Initialise)
    end,
    
    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(3)
        -- ...
        LOG("DilliDalli Brain ready...")
        
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

function CreateBrain(aiBrain)
    local b = Brain()
    b:OnCreate(aiBrain)
    return b
end