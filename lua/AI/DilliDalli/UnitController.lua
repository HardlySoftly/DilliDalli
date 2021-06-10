UnitController = Class({
    Initialise = function(self,brain)
        self.brain = brain
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

function CreateUnitController(brain)
    local uc = UnitController()
    uc:Initialise(brain)
    return uc
end
