local PROFILER = import('/mods/DilliDalli/lua/AI/DilliDalli/Profiler.lua').GetProfiler()

UnitController = Class({
    Initialise = function(self,brain)
        self.brain = brain
        self.land = LandController()
        self.air = AirController()

        self.land:Init(self.brain)
        self.air:Init(self.brain)
    end,

    Run = function(self)
        self.land:Run()
        self.air:Run()
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
        self.groups = {}
        self.groupID = 1
    end,

    Run = function(self)
        self:ForkThread(self.LandControlThread)
        --self:ForkThread(self.GroupLoggingThread)
    end,

    CreateGroup = function(self,unit)
        local lg = LandGroup()
        lg:Init(self.brain,self,self.groupID)
        self.groupID = self.groupID + 1
        table.insert(self.groups,lg)
        lg:Add(unit)
        lg:Run()
    end,

    FindGroup = function(self,unit)
        -- Add this unit to a relevant group
        local best
        local bestPriority = 0
        if EntityCategoryContains(categories.SCOUT,unit) then
            for _, v in self.groups do
                if not v.scout then
                    v:Add(unit)
                    return
                end
            end
        end
        for _, v in self.groups do
            if v.size == 0 then
                continue
            end
            local priority = (5+v.size)/(1+v.zoneThreat)
            if (not best) or priority < bestPriority then
                best = v
                bestPriority = priority
            end
        end
        if (not best) then
            -- Huh??
            WARN("UnitController: Failed to find group...  creating a new one.")
            self:CreateGroup(unit)
        else
            best:Add(unit)
        end
    end,

    FindNewTarget = function(self,pos,id,layer)
        local best
        local bestPriority = 0
        -- TODO: use layer info
        for _, v in self.brain.intel.zones do
            if ((v.control.land.enemy == 0) and (v.control.land.ally > 0)) or (not self.brain.intel:CanPathToSurface(pos,v.pos)) then
                continue
            end
            local found = false
            for _, g in self.groups do
                if g.targetZone and (VDist3(g.targetZone.pos,v.pos) < 5) then
                    found = true
                end
            end
            if (not found) then
                local priority = 1/v.weight
                if table.getn(self.brain.aiBrain:GetUnitsAroundPoint(categories.STRUCTURE,v.pos,30,'Enemy')) > 0 then
                    priority = priority/5
                end
                priority = priority * (100+VDist3(pos,v.pos))
                if (not best) or (priority < bestPriority) then
                    best = v
                    bestPriority = priority
                end
            end
        end
        if best then
            return best
        else
            return self.brain.intel:FindZone(self.brain.intel.enemies[1])
        end
    end,

    CheckGroups = function(self)
        -- Delete dead groups
        local i = 1
        while i <= table.getn(self.groups) do
            if self.groups[i]:Size() == 0 then
                table.remove(self.groups,i)
            else
                i = i+1
            end
        end
    end,

    GroupLoggingThread = function(self)
        while self.brain:IsAlive() do
            --LOG("=========================")
            --for _, v in self.groups do
            --    LOG("Group: "..tostring(v.id)..", size: "..tostring(v.size)..", reinforcing: "..tostring(table.getn(v.reinforcing))..", units: "..tostring(table.getn(v.units)))
            --end
            LOG("Num groups: "..tostring(table.getn(self.groups)))
            local t = 0
            for _, v in self.groups do
                t = t + table.getn(v.units)
                t = t + table.getn(v.reinforcing)
            end
            LOG("Group state size: "..tostring(t))
            WaitTicks(200)
        end
    end,

    LandControlThread = function(self)
        while self.brain:IsAlive() do
            local start = PROFILER:Now()
            self:CheckGroups()
            local units = self.brain.aiBrain:GetListOfUnits(categories.LAND * categories.MOBILE - categories.ENGINEER,false,true)
            local numUnits = table.getn(units)
            local targetNumberOfGroups = math.sqrt(numUnits)*2 + 1
            local numGroups = table.getn(self.groups)
            for _, unit in units do
                if not unit.CustomData then
                    unit.CustomData = {}
                end
                if (not unit.CustomData.landAssigned) and (not unit:IsBeingBuilt()) then
                    unit.CustomData.landAssigned = true
                    if EntityCategoryContains(categories.EXPERIMENTAL,unit) then
                        self:ForkThread(self.ExpThread,unit)
                    elseif numGroups < targetNumberOfGroups then
                        -- Create group
                        self:CreateGroup(unit)
                        numGroups = numGroups + 1
                    else
                        -- Add to group
                        self:FindGroup(unit)
                    end
                end
            end
            -- Multiple coms?  Pretty niche.
            if self.brain.base.isBOComplete then
                local coms = self.brain.aiBrain:GetListOfUnits(categories.COMMAND,false,true)
                for _, v in coms do
                    v.CustomData.excludeAssignment = true
                    if not v.CustomData.landAssigned and not v.CustomData.isAssigned then
                        v.CustomData.landAssigned = true
                        self:ForkThread(self.ACUThread,v)
                    end
                end
            end
            PROFILER:Add("LandControlThread",PROFILER:Now()-start)
            WaitTicks(21)
        end
    end,

    BiasLocation = function(self,pos,target,dist)
        local delta = VDiff(target,pos)
        local norm = VDist2(delta[1],delta[3],0,0)
        local x = pos[1]+dist*delta[1]/norm
        local z = pos[3]+dist*delta[3]/norm
        x = math.min(ScenarioInfo.size[1]-5,math.max(5,x))
        z = math.min(ScenarioInfo.size[2]-5,math.max(5,z))
        return {x,GetSurfaceHeight(x,z),z}
    end,

    ACUThread = function(self,acu)
        local target
        local scared = false
        while self.brain:IsAlive() and acu and (not acu.Dead) do
            if acu:GetHealth() < 6000 and (not scared) then
                target = self:BiasLocation(self.brain.intel.allies[1],self.brain.intel.enemies[1],10)
                scared = true
            elseif scared and acu:GetHealth()/acu:GetBlueprint().Defense.MaxHealth > 0.9 then
                scared = false
                target = nil
            end
            if self.brain.monitor.units.land.mass.total > 2500 then
                target = self:BiasLocation(self.brain.intel.allies[1],self.brain.intel.enemies[1],10)
                scared = true
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
                if VDist3(best,self.brain.intel.enemies[1]) < 80 then
                    target = self:BiasLocation(self.brain.intel.enemies[1],self.brain.intel.allies[1],60)
                else
                    -- Bias target towards enemy base
                    target = self:BiasLocation(best,self.brain.intel.enemies[1],10)
                end
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

    ExpThread = function(self,unit)
        local target = table.copy(self.brain.intel.enemies[1])
        local hurt = false
        local lastPos
        local stationary = false
        while unit and (not unit.Dead) do
            local start = PROFILER:Now()
            local myPos = unit:GetPosition()
            if hurt then
                if unit:GetHealth()/unit:GetBlueprint().Defense.MaxHealth > 0.9 then
                    hurt = false
                    target = table.copy(self.brain.intel.enemies[1])
                    IssueClearCommands({unit})
                    IssueAggressiveMove({unit},target)
                elseif unit:IsIdleState() then
                    local newPos = {target[1] + Random(-20,20),target[2],target[3] + Random(-20,20)}
                    IssueMove({unit},newPos)
                end
            else
                if unit:GetHealth()/unit:GetBlueprint().Defense.MaxHealth < 0.4 then
                    -- Check if we are hurt
                    hurt = true
                    target = table.copy(self.brain.intel.allies[1])
                    IssueClearCommands({unit})
                    IssueMove({unit},target)
                elseif VDist3(myPos, target) < 40 then
                    -- If near the target, move randomly
                    if unit:IsIdleState() then
                        local newPos = {target[1] + Random(-20,20),target[2],target[3] + Random(-20,20)}
                        IssueMove({unit},newPos)
                    end
                elseif lastPos and VDist3(lastPos,myPos) < 1 then
                    stationary = true
                    IssueClearCommands({unit})
                    IssueMove({unit},target)
                elseif stationary then
                    stationary = false
                    IssueClearCommands({unit})
                    IssueAggressiveMove({unit},target)
                end
            end
            lastPos = myPos
            PROFILER:Add("ExpThread",PROFILER:Now()-start)
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

LandGroup = Class({
    Init = function(self,brain,controller,id)
        self.brain = brain
        self.controller = controller
        self.id = id
        self.scout = false

        self.threat = 0
        self.localThreat = 0
        self.localSupport = 0
        self.localThreatPos = 0
        self.zoneThreatAge = 0
        self.zoneThreat = 0

        self.units = {}
        self.reinforcing = {}
        self.targetZone = nil
        self.nextMove = nil

        self.reinforceCounter = 0
        self.radius = 30

        self.size = 0
    end,

    AssaultControlThread = function(self)
        local danger = 0
        local threatened = false
        local targetCounter = 0
        WaitTicks(Random(0,9))
        while self:Resize() > 0 do
            local start = PROFILER:Now()
            local myPos = self:Reinforce()
            if (targetCounter == 0) or (not self.targetZone) or (VDist3(myPos,self.targetZone.pos) < 20 and self.targetZone.control.land.enemy <= 0) then
                self.targetZone = nil
                self.targetZone = self.controller:FindNewTarget(myPos,self.id,'surf')
                targetCounter = 20
                IssueClearCommands(self.units)
                IssueMove(self.units,self.targetZone.pos)
            else
                targetCounter = targetCounter - 1
            end
            -- Go steady if there's danger
            if self.localThreat <= self.localSupport*1.0 then
                if danger > 0 then
                    danger = danger-1
                    if danger == 0 then
                        -- Continue to attack, it's safe
                        IssueClearCommands(self.units)
                        IssueMove(self.units,self.targetZone.pos)
                        self.nextMove = nil
                    end
                end
                if (not threatened) and self.localThreat > self.localSupport*0.4 then
                    threatened = true
                    IssueClearCommands(self.units)
                    IssueAggressiveMove(self.units,self.targetZone.pos)
                    self.nextMove = nil
                elseif threatened and self.localThreat <= self.localSupport*0.4 then
                    threatened = false
                    IssueClearCommands(self.units)
                    IssueMove(self.units,self.targetZone.pos)
                    self.nextMove = nil
                end
            elseif danger < 5 then
                danger = 5
                IssueClearCommands(self.units)
                -- TODO: Some better dodging here
                if self.localThreatPos then
                    self.nextMove = self.controller:BiasLocation(myPos,self.localThreatPos,-40)
                    IssueMove(self.units,self.nextMove)
                end
            end
            PROFILER:Add("AssaultControlThread",PROFILER:Now()-start)
            WaitTicks(10)
        end
    end,

    DangerAt = function(self,pos,radius)
        local enemyUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,pos,radius,'Enemy')
        local neutralUnits = self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,pos,radius,'Enemy')
        local dangerEnemy = self.brain.intel:GetLandThreatAndPos(enemyUnits)
        local dangerNeutral = self.brain.intel:GetLandThreatAndPos(neutralUnits)
        if dangerEnemy.pos and dangerNeutral.pos then
            return { threat = dangerEnemy.threat + dangerNeutral.threat, pos = VMult(VAdd(dangerEnemy.pos,dangerNeutral.pos),0.5)}
        elseif dangerNeutral.pos then
            return dangerNeutral
        else
            return dangerEnemy
        end
    end,

    IntelThread = function(self)
        WaitTicks(Random(0,19))
        while self.size > 0 do
            local start = PROFILER:Now()
            if self.targetZone then
                local myPos = self:Position()
                local nextPos = self.controller:BiasLocation(myPos,self.targetZone.pos,math.min(40,VDist3(myPos,self.targetZone.pos)))
                local threat = self:DangerAt(nextPos,40)
                self.threat = self.brain.intel:GetLandThreat(self.units)
                self.localThreat = threat.threat
                self.localSupport = math.max(self.brain.intel:GetLandThreat(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,myPos,40,'Ally')),
                                             self.brain.intel:GetLandThreat(self.brain.aiBrain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL,nextPos,60,'Ally'))/1.5)
                self.localThreatPos = threat.pos
                if (self.zoneThreatAge >= 10) or (self.zoneThreat < self.targetZone.control.land.enemy) then
                    self.zoneThreatAge = 0
                    self.zoneThreat = self.targetZone.control.land.enemy
                else
                    self.zoneThreatAge = self.zoneThreatAge + 1
                end
            end
            PROFILER:Add("LandIntelThread",PROFILER:Now()-start)
            WaitTicks(20)
        end
    end,

    Add = function(self,unit)
        -- Add unit, issue initial orders
        if EntityCategoryContains(categories.SCOUT,unit) then
            self.scout = true
        end
        table.insert(self.reinforcing,unit)
        self.size = self.size + 1
        if self.targetZone then
            IssueClearCommands({unit})
            IssueMove({unit}, self.targetZone.pos)
        end
    end,

    Position = function(self)
        local x = 0
        local z = 0
        local n = 0
        for _, v in self.units do
            if v and (not v.Dead) then
                local pos = v:GetPosition()
                x = x + pos[1]
                z = z + pos[3]
                n = n+1
            end
        end
        if n == 0 then
            -- We're in our base maybe?????
            return self.brain.intel.allies[1]
        else
            return {x/n, GetSurfaceHeight(x/n,z/n), z/n}
        end
    end,

    Reinforce = function(self)
        -- Move units from reinforcing into units
        if table.getn(self.units) == 0 then
            self.units = self.reinforcing
            self.reinforcing = {}
            if self.targetZone then
                IssueClearCommands(self.units)
                IssueMove(self.units,self.targetZone.pos)
            end
            return self:Position()
        else
            local currentPos = self:Position()
            local moved = {}
            local i = 1
            while i <= table.getn(self.reinforcing) do
                if VDist3(self.reinforcing[i]:GetPosition(),currentPos) < self.radius then
                    table.insert(moved,self.reinforcing[i])
                    table.insert(self.units,self.reinforcing[i])
                    table.remove(self.reinforcing,i)
                else
                    i = i+1
                end
            end
            if self.nextMove then
                IssueClearCommands(moved)
                IssueMove(moved,self.nextMove)
            elseif self.targetZone then
                IssueClearCommands(moved)
                IssueMove(moved,self.targetZone.pos)
            end
            local newPos = self:Position()
            -- IssueMove reinforcing to new position
            if self.reinforceCounter == 0 then
                IssueClearCommands(self.reinforcing)
                IssueMove(self.reinforcing,newPos)
                self.reinforceCounter = 3
            else
                self.reinforceCounter = self.reinforceCounter - 1
            end
            -- Return new position
            return newPos
        end
    end,

    Resize = function(self)
        -- Eliminate dead units, return new size
        local i = 1
        while i <= table.getn(self.units) do
            if (not self.units[i]) or self.units[i].Dead then
                table.remove(self.units,i)
            else
                i = i+1
            end
        end
        local j = 1
        while j <= table.getn(self.reinforcing) do
            if (not self.reinforcing[j]) or self.reinforcing[j].Dead then
                table.remove(self.reinforcing,j)
            else
                j = j+1
            end
        end
        self.size = table.getn(self.units) + table.getn(self.reinforcing)
        return self.size
    end,

    Size = function(self)
        -- Return size
        return self.size
    end,

    Run = function(self)
        self:ForkThread(self.AssaultControlThread)
        self:ForkThread(self.IntelThread)
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

AirController = Class({
    Init = function(self,brain)
        self.brain = brain
        self.groups = {}
        self.groupID = 1
    end,

    Run = function(self)
        self:ForkThread(self.AirControlThread)
    end,

    CreateGroup = function(self,unit)
        local ag = IntieGroup()
        ag:Init(self.brain,self,self.groupID)
        self.groupID = self.groupID + 1
        self.groups = {}
        table.insert(self.groups,ag)
        ag:Add(unit)
        ag:Run()
    end,

    CheckGroups = function(self)
        -- Delete dead groups
        local i = 1
        while i <= table.getn(self.groups) do
            if self.groups[i]:Size() == 0 then
                table.remove(self.groups,i)
            else
                i = i+1
            end
        end
    end,

    FindGroup = function(self,unit)
        -- Add this unit to a relevant group
        local best
        local bestPriority = 0
        for _, v in self.groups do
            local priority = v.size
            if (not best) or priority < bestPriority then
                best = v
                bestPriority = priority
            end
        end
        if (not best) then
            -- Huh??
            WARN("UnitController: Failed to find group...  creating a new one.")
            self:CreateGroup(unit)
        else
            best:Add(unit)
        end
    end,

    ScoutingThread = function(self,scout)
        local targetZone
        while scout and (not scout.Dead) do
            local myPos = scout:GetPosition()
            if (not targetZone) or (VDist2(myPos[1],myPos[3],targetZone.pos[1],targetZone.pos[3]) < 30) or scout:IsIdleState() then
                targetZone = nil
                local bestScore = 0
                for _, v in self.brain.intel.zones do
                    local dist = VDist2(myPos[1],myPos[3],v.pos[1],v.pos[3])
                    local r = Random(100,1000)
                    if (r > bestScore) and (dist >= 50) then
                        targetZone = v
                        bestScore = r
                    elseif (not targetZone) and (dist < 50) then
                        targetZone = v
                    end
                end
                -- Select new target zone and move there
                IssueClearCommands({scout})
                IssueMove({scout},targetZone.pos)
            end
            WaitTicks(10)
        end
    end,

    AirControlThread = function(self)
        while self.brain:IsAlive() do
            self:CheckGroups()
            local units = self.brain.aiBrain:GetListOfUnits(categories.AIR * categories.MOBILE - categories.ENGINEER,false,true)
            local numUnits = table.getn(units)
            local targetNumberOfGroups = 1 + math.floor((math.sqrt(numUnits/10))+0.1)
            local numGroups = table.getn(self.groups)
            for _, unit in units do
                if not unit.CustomData then
                    unit.CustomData = {}
                end
                if (not unit.CustomData.airAssigned) and (not unit:IsBeingBuilt()) then
                    unit.CustomData.airAssigned = true
                    if EntityCategoryContains(categories.SCOUT,unit) then
                        self:ForkThread(self.ScoutingThread,unit)
                    end
                    if numGroups < targetNumberOfGroups then
                        -- Create group
                        self:CreateGroup(unit)
                        numGroups = numGroups + 1
                    else
                        -- Add to group
                        self:FindGroup(unit)
                    end
                end
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

IntieGroup = Class({
    Init = function(self,brain,controller,id)
        self.brain = brain
        self.controller = controller
        self.id = id

        self.units = {}
        self.size = 0
    end,

    InterceptionThread = function(self)
        local targetZone = nil
        local waiting = false
        while self:Resize() > 0 do
            if (not targetZone) or (self.units[1]:IsIdleState() and (not waiting)) or (targetZone.control.land.ally < targetZone.control.land.enemy) then
                targetZone = nil
                local bestThreat = 0
                local bestSafety = 0
                for _, v in self.brain.intel.zones do
                    local r = Random(1,100)
                    if (v.control.land.ally > v.control.land.enemy) and v.control.air.enemy > bestThreat then
                        targetZone = v
                        bestThreat = v.control.air.enemy
                        waiting = false
                    elseif (bestThreat == 0) and (r > bestSafety) then
                        bestSafety = r
                        targetZone = v
                        waiting = true
                    end
                end
                if targetZone then
                    IssueClearCommands(self.units)
                    IssueAggressiveMove(self.units,targetZone.pos)
                end
            end
            WaitTicks(20)
        end
    end,

    Add = function(self,unit)
        table.insert(self.units,unit)
        self.size = self.size + 1
    end,

    Run = function(self)
        self:ForkThread(self.InterceptionThread)
    end,

    Resize = function(self)
        local i = 1
        while i <= table.getn(self.units) do
            if self.units[i] and (not self.units[i].Dead) then
                i = i+1
            else
                table.remove(self.units,i)
            end
        end
        self.size = table.getn(self.units)
        return self.size
    end,

    Size = function(self)
        return self.size
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
