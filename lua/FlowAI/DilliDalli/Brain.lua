local BC = import('/mods/DilliDalli/lua/FlowAI/framework/BaseController.lua')
--local IM = import('/mods/DilliDalli/lua/AI/DilliDalli/IntelManager.lua')
--local AM = import('/mods/DilliDalli/lua/AI/DilliDalli/ArmyMonitor.lua')
--local UC = import('/mods/DilliDalli/lua/AI/DilliDalli/UnitController.lua')
--local PM = import('/mods/DilliDalli/lua/AI/DilliDalli/ProductionManager.lua')
local PM = import('/mods/DilliDalli/lua/FlowAI/framework/EconomyManager.lua')


Brain = Class({
    Init = function(self,aiBrain)
        self.aiBrain = aiBrain
        self.Trash = TrashBag()
        self:ForkThread(self.Initialise)
    end,

    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(5)
        -- ...
        self.base = BC.CreateBaseController(self)
        --self.intel = IM.CreateIntelManager(self)
        --self.monitor = AM.CreateArmyMonitor(self)
        --self.army = UC.CreateUnitController(self)
        self.eco = PM.CreateProductionManager(self)
        self.eco:SetPriority({ weights = {ual0201 = 1.0, uel0201 = 1.0, url0107 = 1.0, xsl0201 = 1.0}, globalWeight = 1.0})
        LOG("DilliDalli Brain ready...")
        self.eco:Run()
        --bo = self.intel:PickBuildOrder()
        -- Make sure to copy items so that different AIs don't end up sharing variables (learned that the hard way)
        --for _, v in bo.mobile do
        --    self.base:AddMobileJob(table.copy(v))
        --end
        --for _, v in bo.factory do
        --    self.base:AddFactoryJob(table.copy(v))
        --end
        --self.base:Run()
        --self.intel:Run()
        --self.monitor:Run()
        --WaitSeconds(2)
        --self.production:Run()
        --self.army:Run()
    end,

    IsAlive = function(self)
        return self.aiBrain.Result ~= "defeat"
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
    b:Init(aiBrain)
    return b
end