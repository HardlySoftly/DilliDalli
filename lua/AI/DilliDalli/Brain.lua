local BC = import('/mods/DilliDalli/lua/AI/DilliDalli/BaseController.lua')
local IM = import('/mods/DilliDalli/lua/AI/DilliDalli/IntelManager.lua')

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
        LOG("DilliDalli Brain ready...")
        bo = self.intel:PickBuildOrder()
        for _, v in bo.mobile do
            self.base:AddMobileJob(v)
        end
        for _, v in bo.factory do
            self.base:AddFactoryJob(v)
        end
        self.base:Run()
    end,
    
    IsAlive = function(self)
        return self.aiBrain.Result ~= "defeat"
    end,

    GetEngineers = function(self)
        local units = self.aiBrain:GetListOfUnits(categories.MOBILE*categories.ENGINEER,false,true)
        local n = 0
        local engies = {}
        for _, v in units do
            if (not v.CustomData or ((not v.CustomData.excludeEngie) and (not v.CustomData.engieAssigned))) and not v:IsBeingBuilt() then
                n = n+1
                engies[n] = v
            end
        end
        --LOG("Engies found: "..tostring(table.getn(engies)))
        return engies
    end,

    GetFactories = function(self)
        local units = self.aiBrain:GetListOfUnits(categories.STRUCTURE*categories.FACTORY,false,true)
        local n = 0
        local facs = {}
        for _, v in units do
            if not v.CustomData or ((not v.CustomData.excludeFac) and (not v.CustomData.facAssigned)) then
                n = n+1
                facs[n] = v
            end
        end
        return facs
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