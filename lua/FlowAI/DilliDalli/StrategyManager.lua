StrategyManager = Class({
    Init = function(self)
    end,
})

function CreateStrategyManager()
    local sm = StrategyManager()
    sm:Init()
    return sm
end
