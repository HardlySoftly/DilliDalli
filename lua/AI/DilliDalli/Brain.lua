local BC = import('/mods/DilliDalli/lua/AI/DilliDalli/BaseController.lua')
local IM = import('/mods/DilliDalli/lua/AI/DilliDalli/IntelManager.lua')
local AM = import('/mods/DilliDalli/lua/AI/DilliDalli/ArmyMonitor.lua')
local AM = import('/mods/DilliDalli/lua/AI/DilliDalli/UnitController.lua')

Brain = Class({
    OnCreate = function(self,aiBrain)
        self.aiBrain = aiBrain
        self.Trash = TrashBag()
        self:ForkThread(self.Initialise)
    end,

    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(5)
        -- ...
        self.base = BC.CreateBaseController(self)
        self.intel = IM.CreateIntelManager(self)
        self.monitor = AM.CreateArmyMonitor(self)
        self.army = UC.CreateUnitController(self)
        LOG("DilliDalli Brain ready...")
        bo = self.intel:PickBuildOrder()
        -- make sure to copy items so that different AIs don't end up sharing variables
        for _, v in bo.mobile do
            self.base:AddMobileJob(table.copy(v))
        end
        for _, v in bo.factory do
            self.base:AddFactoryJob(table.copy(v))
        end
        self.base:Run()
        -- BO should give us enough time to get all our other bits off the ground.
        self:ForkThread(self.ProductionControllerThread)
    end,

    ProductionControllerThread = function(self)
        local tankJob = self.base:CreateGenericJob()
        tankJob.work = "DirectFireT1"
        tankJob.priority = 1000
        tankJob.count = 10000000
        tankJob.duplicates = 2
        self.base:AddFactoryJob(tankJob)
        local mexJob = self.base:CreateGenericJob()
        mexJob.work = "MexT1"
        mexJob.priority = 1000
        mexJob.count = 10000000
        mexJob.duplicates = 2
        self.base:AddMobileJob(mexJob)
        while self:IsAlive() do

            WaitSeconds(1)
        end
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
    b:OnCreate(aiBrain)
    return b
end