UnitController = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.land = LandController()

        self.land:Init(self.brain)
    end,

    Run = function(self)
        self.land:Run()
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

LandController = Class({
    Init = function(self,brain)
        self.brain = brain
        self.detectRadius = 60
    end,

    Run = function(self)
        self:ForkThread(self.LandControlThread)
    end,

    LandControlThread = function(self)
        while self.brain:IsAlive() do
            local units = self.brain.aiBrain:GetListOfUnits(categories.LAND * categories.MOBILE - categories.ENGINEER,false,true)
            for _, unit in units do
                if not unit.CustomData then
                    unit.CustomData = {}
                end
                if not unit.CustomData.found then
                    unit.CustomData.found = true
                    unit.CustomData.assigned = false
                    self:ForkThread(self.UnitControlThread, unit)
                end
            end
            -- Multiple coms?  Pretty niche.
            if self.brain.base.isBOComplete then
                local coms = self.brain.aiBrain:GetListOfUnits(categories.COMMAND,false,true)
                for _, v in coms do
                    v.CustomData.excludeAssignment = true
                    if not v.CustomData.assigned and not v.CustomData.isAssigned then
                        v.CustomData.assigned = true
                        self:ForkThread(self.ACUThread,v)
                    end
                end
            end
            WaitTicks(20)
        end
    end,
    
    UnitControlThread = function(self, unit)
        -- While not under threat, move from zone to zone
        local threat = 0
        local targetZone
        while self.brain:IsAlive() and unit and not unit.Dead and threat <= 0.5 and not unit.CustomData.assigned do
            if unit and not unit.Dead and not unit.CustomData.assigned then
                threat = self.brain.intel:GetLandThreat(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,unit:GetPosition(),self.detectRadius/1.5,'Enemy'))
            end
            -- Now find something to do
            if (not targetZone) or VDist3(unit:GetPosition(),targetZone) < 20 or unit:IsIdleState() then
                local bestR = 0
                local bestPos
                for _, z in self.brain.intel.zones do
                    local r = Random(10,1000)
                    if r > bestR and VDist3(self.brain.intel.enemies[1],z.pos) <= VDist3(unit:GetPosition(),self.brain.intel.enemies[1]) then
                        bestR = r
                        bestPos = z.pos
                    end
                end
                if not bestPos then
                    bestPos = self.brain.intel.enemies[1]
                end
                targetZone = bestPos
                IssueClearCommands({unit})
                IssueMove({unit},targetZone)
            end
            WaitTicks(20)
        end
        if unit and not unit.Dead and not unit.CustomData.assigned and threat > 0.5 then
           self:CreateGroup(unit)
           return
        end
    end,
    
    CreateGroup = function(self, unit)
        -- Find nearby units
        local units = {unit}
        unit.CustomData.assigned = true
        local myIndex = self.brain.aiBrain:GetArmyIndex()
        local candidates = self.brain.aiBrain:GetUnitsAroundPoint(categories.LAND * categories.MOBILE - categories.ENGINEER,unit:GetPosition(),self.detectRadius,'Ally')
        for _, v in candidates do
            if (not (v:GetArmy() == myIndex)) or v.CustomData.assigned then
                continue
            end
            v.CustomData.assigned = true
            table.insert(units,v)
        end
        -- Start GroupControlThread
        self:GroupControlThread(units)
    end,
    
    GetPosition = function(self, units)
        local x = 0
        local z = 0
        local n = 0
        for _, v in units do
            local pos = v:GetPosition()
            n = n+1
            x = x+pos[1]
            z = z+pos[3]
        end
        n = math.max(n,1)
        return {x/n,GetSurfaceHeight(x/n,z/n),z/n}
    end,
    
    GroupControlThread = function(self, units)
        local group = table.copy(units)
        local retreat = 0
        while self.brain:IsAlive() do
            -- tidy up group, return if it's empty (i.e. all units dead)
            local index = 1
            while index ~= 0 do
                index = 0
                for k, v in group do
                    if not v or v.Dead then
                        index = k
                        break
                    end
                end
                if index ~= 0 then
                    table.remove(group,index)
                end
            end
            if table.getn(group) == 0 then
                return
            end
            -- Detect if we're outnumbered
            local pos = self:GetPosition(group)
            local enemyUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,pos,self.detectRadius,'Enemy')
            local alliedUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS,pos,self.detectRadius,'Ally')
            local enemyThreat = self.brain.intel:GetLandThreat(enemyUnits)
            local alliedThreat = self.brain.intel:GetLandThreat(alliedUnits)
            if enemyThreat > alliedThreat then
                retreat = 5
            end
            -- Retreat if we've been recently outnumbered
            if retreat > 0 then
                if enemyThreat * 1.2 > alliedThreat then
                    retreat = 5
                else
                    retreat = retreat - 1
                end
                if retreat == 5 then
                    -- If enemy units in the vicinity then move away TODO
                    local enemyPos = self:GetPosition(enemyUnits)
                    local retreatVector = { enemyPos[1]-pos[1], enemyPos[3]-pos[3] }
                    local retreatVectorSize = math.max(VDist2(retreatVector[1], retreatVector[2], 0, 0),1)
                    -- Retreating is actually attacking right now...
                    local retreatDistance = 40
                    local targetPos = { pos[1]+retreatDistance*retreatVector[1]/retreatVectorSize, pos[3]+retreatDistance*retreatVector[2]/retreatVectorSize }
                    IssueClearCommands(group)
                    IssueMove(group,{targetPos[1],GetSurfaceHeight(targetPos[1],targetPos[2]),targetPos[2]})
                else
                    -- Move towards a safe zone TODO
                    -- Just continue previous order for now????
                end
            elseif retreat == 0 then
                retreat = -1
                IssueClearCommands(group)
                IssueMove(group,self.brain.intel.enemies[1])
                -- Find something to attack
                if enemyThreat < alliedThreat then
                    -- Attack units TODO
                else
                    -- Offensive move to a zone TODO
                end
            end
            WaitTicks(10)
        end
    end,

    BiasLocation = function(self,pos,target,dist)
        local delta = VDiff(target,pos)
        local norm = VDist2(delta[1],delta[3],0,0)
        local x = pos[1]+dist*delta[1]/norm
        local z = pos[3]+dist*delta[3]/norm
        return {x,GetSurfaceHeight(x,z),z}
    end,

    ACUThread = function(self,acu)
        local target
        local scared = false
        while self.brain:IsAlive() and acu and not acu.Dead do
            if acu:GetHealth()/acu:GetBlueprint().Defense.MaxHealth < 0.4 and (not scared) then
                target = self:BiasLocation(self.brain.intel.allies[1],self.brain.intel.enemies[1],10)
                scared = true
            elseif scared and acu:GetHealth()/acu:GetBlueprint().Defense.MaxHealth > 0.9 then
                scared = false
                target = nil
            end
            if not target then
                local best
                local bestMetric = 0
                for _, v in self.brain.intel.zones do
                    local d0 = VDist3(self.brain.intel.allies[1],v.pos)
                    local d1 = VDist3(self.brain.intel.enemies[1],v.pos)
                    local metric = v.weight/(100+math.abs(d0-2*d1))
                    if (not best) or metric > bestMetric then
                        best = v.pos
                        bestMetric = metric
                    end
                end
                -- Bias target towards enemy base
                target = self:BiasLocation(best,self.brain.intel.enemies[1],10)
            end
            if VDist3(acu:GetPosition(),target) > 20 then
                -- If too far away move nearer
                IssueClearCommands({acu})
                IssueMove({acu},target)
            elseif acu:IsIdleState() then
                -- Else if idle move somewhere random nearby
                local newPos = {target[1] + Random(-15,15),target[2],target[3] + Random(-15,15)}
                IssueMove({acu},newPos)
            end
            WaitTicks(20)
        end
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
