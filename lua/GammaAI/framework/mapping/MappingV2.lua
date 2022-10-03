--[[
    To use this code:
    1) Hook _G.SetPlayableRect and call SetPlayableArea
    2) Hook BeginSession and call OnBeginSession
    3) Profit (you may wish to edit some of the logging in or out - see OnBeginSession and the end of GameMap:Init)
]]

-- Playable Area hook
local DEFAULT_BORDER = 0
local PLAYABLE_AREA = nil
function SetPlayableArea(x0,z0,x1,z1)
    -- Necessary for maps with custom playable areas, e.g. Fields of Isis.
    PLAYABLE_AREA = { math.floor(x0), math.floor(z0), math.ceil(x1), math.ceil(z1) }
end

-- CONSTANTS
-- Maximum pathable gradient
local MAX_GRADIENT = 0.75
local MAX_DEPTH_LAND = 0.0
local MAX_DEPTH_AMPHIBIOUS = 25
local MIN_DEPTH_NAVY = 1.5

---@alias GenLayer
--- | '1' # Land layer 
--- | '2' # Navy layer
--- | '3' # Hover layer
--- | '4' # Amph layer

-- Some constants so we can refer to specific layers later
local LAYER_LAND = 1
local LAYER_NAVY = 2
local LAYER_HOVER = 3
local LAYER_AMPH = 4
-- For editing the size of the MapArea objects.
local MAP_AREA_SIZE = 32

-- A helper class that implements a Set, used by ConnectivityMatrix
---@class ConnectivitySet
---@field size number
---@field items table
ConnectivitySet = ClassSimple({
    Init = function(self)
        self.size = 0
        self.items = {}
    end,

    Add = function(self, item)
        -- No binary search here, probably minimal performance benefits to it
        for i = 1, self.size do
            if self.items[i] == item then
                return true
            end
        end
        self.size = self.size + 1
        self.items[self.size] = item
        return false
    end,
})

--- Class used to track connections between potential components, and then translate to a minimal set of components
---@class ConnectivityMatrix 
---@field maxComponentNumber number
---@field numComponents number
---@field matrix ConnectivitySet[]
---@field translation number[]
ConnectivityMatrix = ClassSimple({
    Init = function(self)
        self.maxComponentNumber = 0
        self.matrix = {}
    end,

    --- Collapse created components based on the connections identified. Performs a search through the connectivity matrix it has built
    ---@param self ConnectivityMatrix
    MergeComponents = function(self)
        local numComponents = 0

        -- Translation is from originally assigned component number to the final true component number
        local translation = {}
        for i = 1, self.maxComponentNumber do
            -- A translation of -1 implies a search needs to be performed and a component assigned
            translation[i] = -1
        end
        for i = 1, self.maxComponentNumber do
            if translation[i] == -1 then
                numComponents = numComponents + 1
                local work = {i}
                local workLen = 1
                while workLen > 0 do
                    local k = work[1]
                    work[1] = work[workLen]
                    work[workLen] = nil
                    workLen = workLen - 1
                    if translation[k] == -1 then
                        translation[k] = numComponents
                        for j = 1, self.matrix[k].size do
                            local item = self.matrix[k].items[j]
                            if translation[item] == -1 then
                                workLen = workLen + 1
                                work[workLen] = item
                            end
                        end
                    end
                end
            end
        end
        self.translation = translation
        self.numComponents = numComponents
    end,

    --- Returns a new component number
    ---@param self ConnectivityMatrix
    ---@return number
    AddComponent = function(self)
        self.maxComponentNumber = self.maxComponentNumber + 1
        local cs = ConnectivitySet()
        cs:Init()
        self.matrix[self.maxComponentNumber] = cs
        return self.maxComponentNumber
    end,

    --- Inform the ConnectivityMatrix of a connection between two components. a and b must both be in the range [1,maxComponentNumber] inclusive, a ~= b
    ---@param self ConnectivityMatrix
    ---@param a ConnectivitySet
    ---@param b ConnectivitySet
    AddConnection = function(self, a, b)
        self.matrix[a]:Add(b)
        self.matrix[b]:Add(a)
    end,

    --- Translate from initial component numbers to final component numbers (do this after calling MergeComponents)
    ---@param self ConnectivityMatrix
    ---@param a number
    ---@return number
    Translate = function(self, a)
        if a <= 0 then
            return a
        end
        return self.translation[a]
    end,

    --- Returns how many connections between the original components exist
    ---@param self ConnectivityMatrix
    ---@return number
    CountEdges = function(self)
        local res = 0
        for i = 1, self.maxComponentNumber do
            res = res + self.matrix[i].size
        end
        return res/2
    end,
})

---@class MapArea
---@field xOffset number
---@field zOffset number
---@field maxi number
---@field maxj number
---@field compressLand boolean 
---@field compressNavy boolean 
---@field compressHover boolean 
---@field compressAmph boolean
---@field passableLand boolean | boolean[][]        # is a boolean if compressLand is true
---@field passableNavy boolean | boolean[][]        # is a boolean if compressNavy is true
---@field passableHover boolean | boolean [][]      # is a boolean if compressHover is true
---@field passableAmph boolean | boolean[][]        # is a boolean if compressAmph is true
---@field componentLand ConnectivityMatrix
---@field componentNavy ConnectivityMatrix
---@field componentHover ConnectivityMatrix
---@field componentAmph ConnectivityMatrix
---@field negX number
---@field negY number
---@field posX number
---@field posZ number
MapArea = ClassSimple({

    ---Initialise this MapArea and generate layer passability
    ---@param self MapArea
    ---@param xOffset number
    ---@param zOffset number
    Init = function(self, xOffset, zOffset)
        self.xOffset = xOffset
        self.zOffset = zOffset
        self:InitPassable(xOffset,zOffset)
    end,

    --- Determine the passability of the map within this area. Do all layers together, because although it's messy you make some efficiency savings on calls to terrain height, depth calculations, etc
    ---@param self MapArea
    ---@param xOffset number
    ---@param zOffset number
    InitPassable = function(self, xOffset, zOffset)
        -- Localise some commonly called functions
        local mathabs = math.abs
        local mathmin = math.min
        local mathmax = math.max
        -- Save the size of the internal arrays
        local maxi = mathmin(MAP_AREA_SIZE, PLAYABLE_AREA[3]-xOffset)
        local maxj = mathmin(MAP_AREA_SIZE, PLAYABLE_AREA[4]-zOffset)
        self.maxi = maxi
        self.maxj = maxj
        -- Turns out you only need terrain height and water depth; surface height doesn't seem to be used for the hover layer
        local terrain = {}
        local depth = {}
        for i = 1, maxi+1 do
            local x = i+xOffset-1
            terrain[i] = {}
            depth[i] = {}
            for j = 1, maxj+1 do
                local z = j+zOffset-1
                local t = GetTerrainHeight(x,z)
                terrain[i][j] = t
                depth[i][j] = GetSurfaceHeight(x,z) - t
            end
        end
        -- Calculate terrain height deltas; X direction then Z direction.
        local deltaX = {}
        for i = 1, maxi do
            deltaX[i] = {}
            for j = 1, maxj+1 do
                deltaX[i][j] = mathabs(terrain[i][j] - terrain[i+1][j]) <= MAX_GRADIENT
            end
        end
        local deltaZ = {}
        for i = 1, maxi+1 do
            deltaZ[i] = {}
            for j = 1, maxj do
                deltaZ[i][j] = mathabs(terrain[i][j] - terrain[i][j+1]) <= MAX_GRADIENT
            end
        end
        -- Determine passability
        local passableLand = {}
        local passableNavy = {}
        local passableHover = {}
        local passableAmph = {}
        for i = 1, maxi do
            passableLand[i] = {}
            passableNavy[i] = {}
            passableHover[i] = {}
            passableAmph[i] = {}
            for j = 1, maxj do
                local maxDepth = mathmax(depth[i][j],depth[i+1][j],depth[i+1][j+1],depth[i][j+1])
                local minDepth = mathmin(depth[i][j],depth[i+1][j],depth[i+1][j+1],depth[i][j+1])
                local terrainPassable = (deltaX[i][j] and deltaZ[i][j] and deltaX[i][j+1] and deltaZ[i+1][j])
                passableLand[i][j] = (maxDepth <= MAX_DEPTH_LAND) and terrainPassable
                passableNavy[i][j] = (minDepth >= MIN_DEPTH_NAVY)
                passableHover[i][j] = (minDepth > 0) or terrainPassable
                passableAmph[i][j] = (maxDepth <= MAX_DEPTH_AMPHIBIOUS) and terrainPassable
            end
        end
        -- Detect if passability can be compressed for any layer
        local compressLand = true
        local compressNavy = true
        local compressHover = true
        local compressAmph = true
        for i = 1, maxi do
            for j = 1, maxj do
                compressLand = compressLand and (passableLand[i][j] == passableLand[1][1])
                compressNavy = compressNavy and (passableNavy[i][j] == passableNavy[1][1])
                compressHover = compressHover and (passableHover[i][j] == passableHover[1][1])
                compressAmph = compressAmph and (passableAmph[i][j] == passableAmph[1][1])
            end
        end
        -- Save out results of passability
        if compressLand then
            self.passableLand = passableLand[1][1]
        else
            self.passableLand = passableLand
        end
        if compressNavy then
            self.passableNavy = passableNavy[1][1]
        else
            self.passableNavy = passableNavy
        end
        if compressHover then
            self.passableHover = passableHover[1][1]
        else
            self.passableHover = passableHover
        end
        if compressAmph then
            self.passableAmph = passableAmph[1][1]
        else
            self.passableAmph = passableAmph
        end
        self.compressLand = compressLand
        self.compressNavy = compressNavy
        self.compressHover = compressHover
        self.compressAmph = compressAmph
    end,

    --- Generate component numbers within this MapArea; assumes neighbours have been provided where relevant. Assumes GenerateComponents() has already been called on neighbours in the negative X and Z directions.
    ---@param self MapArea
    ---@param landMatrix ConnectivityMatrix
    ---@param navyMatrix ConnectivityMatrix
    ---@param hoverMatrix ConnectivityMatrix
    ---@param amphMatrix ConnectivityMatrix
    GenerateComponents = function(self, landMatrix, navyMatrix, hoverMatrix, amphMatrix)
        self.componentLand = self:GenerateLayerComponents(self.compressLand, self.passableLand, landMatrix, LAYER_LAND)
        self.componentNavy = self:GenerateLayerComponents(self.compressNavy, self.passableNavy, navyMatrix, LAYER_NAVY)
        self.componentHover = self:GenerateLayerComponents(self.compressHover, self.passableHover, hoverMatrix, LAYER_HOVER)
        self.componentAmph = self:GenerateLayerComponents(self.compressAmph, self.passableAmph, amphMatrix, LAYER_AMPH)
    end,

    --- Internal method; generic code for determining initial component numbers
    ---@param self MapArea
    ---@param compressed boolean
    ---@param passable boolean | boolean[][]
    ---@param matrix ConnectivityMatrix
    ---@param layer GenLayer
    ---@return ConnectivityMatrix | number
    GenerateLayerComponents = function(self, compressed, passable, matrix, layer)
        local mathmin = math.min
        local maxi = self.maxi
        local maxj = self.maxj

        ---@type table | number
        local component = {}
        if compressed then
            component = 0
            if passable then
                if self.negZ ~= nil then
                    for i = 1, maxi do
                        local negZComponent = self.negZ:GetComponent(i, MAP_AREA_SIZE, layer)
                        if (negZComponent > 0) and (component > 0) then
                            if component ~= negZComponent then
                                matrix:AddConnection(component,negZComponent)
                                component = mathmin(component,negZComponent)
                            end
                        elseif negZComponent > 0 then
                            component = negZComponent
                        end
                    end
                end
                if self.negX ~= nil then
                    for j = 1, maxj do
                        local negXComponent = self.negX:GetComponent(MAP_AREA_SIZE, j, layer)
                        if (negXComponent > 0) and (component > 0) then
                            if component ~= negXComponent then
                                matrix:AddConnection(component,negXComponent)
                                component = mathmin(component,negXComponent)
                            end
                        elseif negXComponent > 0 then
                            component = negXComponent
                        end
                    end
                end
                if component == 0 then
                    component = matrix:AddComponent()
                end
            end
        else
            for i = 1, maxi do
                component[i] = {}
                for j = 1, maxj do
                    if not passable[i][j] then
                        component[i][j] = 0
                    else
                        -- Get the component for the preceding negative X
                        local negXComponent = 0
                        if i == 1 then
                            if self.negX ~= nil then
                                negXComponent = self.negX:GetComponent(MAP_AREA_SIZE, j, layer)
                            end
                        else
                            negXComponent = component[i-1][j]
                        end
                        -- Get the component for the preceding negative Z
                        local negZComponent = 0
                        if j == 1 then
                            if self.negZ ~= nil then
                                negZComponent = self.negZ:GetComponent(i, MAP_AREA_SIZE, layer)
                            end
                        else
                            negZComponent = component[i][j-1]
                        end
                        -- Set component for current (i,j)
                        if (negXComponent == 0) and (negZComponent == 0) then
                            component[i][j] = matrix:AddComponent()
                        elseif negXComponent == 0 then
                            component[i][j] = negZComponent
                        elseif negZComponent == 0 then
                            component[i][j] = negXComponent
                        elseif negXComponent ~= negZComponent then
                            component[i][j] = mathmin(negXComponent,negZComponent)
                            matrix:AddConnection(negXComponent,negZComponent)
                        else
                            component[i][j] = negXComponent
                        end
                    end
                end
            end
        end
        return component
    end,

    --- Internal method; used by neighbouring MapAreas to spread component numbers between MapAreas
    ---@param self MapArea
    ---@param i number
    ---@param j number
    ---@param layer GenLayer
    ---@return ConnectivityMatrix
    GetComponent = function(self, i, j, layer)
        if layer == LAYER_LAND then
            if self.compressLand then
                return self.componentLand
            else
                return self.componentLand[i][j]
            end
        elseif layer == LAYER_NAVY then
            if self.compressNavy then
                return self.componentNavy
            else
                return self.componentNavy[i][j]
            end
        elseif layer == LAYER_HOVER then
            if self.compressHover then
                return self.componentHover
            else
                return self.componentHover[i][j]
            end
        elseif layer == LAYER_AMPH then
            if self.compressAmph then
                return self.componentAmph
            else
                return self.componentAmph[i][j]
            end
        end
    end,

    --- Called after all components have been generated, translates all connected component numbers to a single component number based on the ConnectivityMatrix
    ---@param self MapArea
    ---@param landMatrix ConnectivityMatrix
    ---@param navyMatrix ConnectivityMatrix
    ---@param hoverMatrix ConnectivityMatrix
    ---@param amphMatrix ConnectivityMatrix
    TranslateComponents = function(self, landMatrix, navyMatrix, hoverMatrix, amphMatrix)
        self.componentLand = self:TranslateLayerComponents(self.compressLand, self.componentLand, landMatrix)
        self.componentNavy = self:TranslateLayerComponents(self.compressNavy, self.componentNavy, navyMatrix)
        self.componentHover = self:TranslateLayerComponents(self.compressHover, self.componentHover, hoverMatrix)
        self.componentAmph = self:TranslateLayerComponents(self.compressAmph, self.componentAmph, amphMatrix)
    end,

    --- Internal method; generic code for translating from provisional to final component numbers
    ---@param self MapArea
    ---@param compressed boolean
    ---@param component number
    ---@param matrix ConnectivityMatrix
    ---@return number
    TranslateLayerComponents = function(self, compressed, component, matrix)
        if compressed then
            return matrix:Translate(component)
        else
            local maxi = self.maxi
            local maxj = self.maxj
            for i = 1, maxi do
                for j = 1, maxj do
                    component[i][j] = matrix:Translate(component[i][j])
                end
            end
        end
        return component
    end,

    --- A way to add neighbours to this MapArea.  Neighbours may be nil, for example at the map border.
    ---@param self MapArea
    ---@param negX number
    ---@param negZ number
    ---@param posX number
    ---@param posZ number
    AddNeighbors = function(self, negX, negZ, posX, posZ)
        self.negX = negX
        self.negZ = negZ
        self.posX = posX
        self.posZ = posZ
    end,
    
    --- A way to draw components so you can visualise the components generated
    ---@param self MapArea
    ---@param sparsity number
    ---@param compress boolean
    ---@param component ConnectivityMatrix
    DrawGenericComponents = function(self, sparsity, compress, component)
        local colours = { 'aa1f77b4', 'aaff7f0e', 'aa2ca02c', 'aad62728', 'aa9467bd', 'aa8c564b', 'aae377c2', 'aa7f7f7f', 'aabcbd22', 'aa17becf' }
        if compress then
            if component > 0 then
                local x = self.xOffset + self.maxi/2
                local z = self.zOffset + self.maxj/2
                DrawCircle({x,GetSurfaceHeight(x,z),z},math.min(self.maxi,self.maxj)/2,colours[math.mod(component-1,10)+1])
            end
        else
            for i = 1, self.maxi do
                if math.mod(i,sparsity) == 0 then
                    local x  = i + self.xOffset - 0.5
                    for j = 1, self.maxj do
                        if math.mod(j,sparsity) == 0 then
                            local z = j+self.zOffset-0.5
                            if component[i][j] > 0 then
                                DrawCircle({x,GetSurfaceHeight(x,z),z},0.5,colours[math.mod(component[i][j]-1,10)+1])
                            end
                        end
                    end
                end
            end
        end
    end,

    ---@param self MapArea
    ---@param sparsity number
    DrawLandComponents = function(self, sparsity)
        self:DrawGenericComponents(sparsity, self.compressLand, self.componentLand)
    end,

    ---@param self MapArea
    ---@param sparsity number
    DrawNavyComponents = function(self, sparsity)
        self:DrawGenericComponents(sparsity, self.compressNavy, self.componentNavy)
    end,

    ---@param self MapArea
    ---@param sparsity number
    DrawHoverComponents = function(self, sparsity)
        self:DrawGenericComponents(sparsity, self.compressHover, self.componentHover)
    end,

    ---@param self MapArea
    ---@param sparsity number
    DrawAmphComponents = function(self, sparsity)
        self:DrawGenericComponents(sparsity, self.compressAmph, self.componentAmph)
    end,
})

---@class GameMap
---@field maxi number
---@field maxj number
---@field mapAreas MapArea[][]
GameMap = ClassSimple({
    Init = function(self)
        WARN("Starting map initialisation!")
        _ALERT("Playable Area:",PLAYABLE_AREA[1],PLAYABLE_AREA[2],PLAYABLE_AREA[3],PLAYABLE_AREA[4])
        -- For ease of reading
        local minx = PLAYABLE_AREA[1]
        local maxx = PLAYABLE_AREA[3]
        local minz = PLAYABLE_AREA[2]
        local maxz = PLAYABLE_AREA[4]
        -- Initialise map areas
        local maxi = math.ceil((maxx-minx)/MAP_AREA_SIZE)
        self.maxi = maxi
        local maxj = math.ceil((maxz-minz)/MAP_AREA_SIZE)
        self.maxj = maxj
        WARN("Map Area objects on a "..tostring(maxi).." by "..tostring(maxj).." grid")
        local mapAreas = {}
        self.mapAreas = mapAreas
        -- Generate MapArea passability
        for i = 1, maxi do
            local xOffset = minx + (i-1)*MAP_AREA_SIZE
            mapAreas[i] = {}
            for j = 1, maxj do
                local zOffset = minz + (j-1)*MAP_AREA_SIZE
                local ma = MapArea()
                ma:Init(xOffset,zOffset)
                mapAreas[i][j] = ma
            end
        end
        -- Add MapArea neighbours
        for i = 1, maxi do
            for j = 1, maxj do
                local negX = nil
                if i > 1 then
                    negX = mapAreas[i-1][j]
                end
                local negZ = nil
                if j > 1 then
                    negZ = mapAreas[i][j-1]
                end
                local posX = nil
                if i < maxi then
                    posX = mapAreas[i+1][j]
                end
                local posZ = nil
                if j < maxj then
                    posZ = mapAreas[i][j+1]
                end
                mapAreas[i][j]:AddNeighbors(negX,negZ,posX,posZ)
            end
        end
        -- Calculate component numbers
        local landMatrix = ConnectivityMatrix()
        landMatrix:Init()
        local navyMatrix = ConnectivityMatrix()
        navyMatrix:Init()
        local hoverMatrix = ConnectivityMatrix()
        hoverMatrix:Init()
        local amphMatrix = ConnectivityMatrix()
        amphMatrix:Init()
        for i = 1, maxi do
            for j = 1, maxj do
                mapAreas[i][j]:GenerateComponents(landMatrix, navyMatrix, hoverMatrix, amphMatrix)
            end
        end
        landMatrix:MergeComponents()
        navyMatrix:MergeComponents()
        hoverMatrix:MergeComponents()
        amphMatrix:MergeComponents()
        for i = 1, maxi do
            for j = 1, maxj do
                mapAreas[i][j]:TranslateComponents(landMatrix, navyMatrix, hoverMatrix, amphMatrix)
            end
        end

        -- Optional Logging
        WARN(
            "Initial Land Components: "..tostring(landMatrix.maxComponentNumber)..
            ", Edges: "..tostring(landMatrix:CountEdges())..
            ", Final Land Components: "..tostring(landMatrix.numComponents)
        )
        WARN(
            "Initial Navy Components: "..tostring(navyMatrix.maxComponentNumber)..
            ", Edges: "..tostring(navyMatrix:CountEdges())..
            ", Final Navy Components: "..tostring(navyMatrix.numComponents)
        )
        WARN(
            "Initial Hover Components: "..tostring(hoverMatrix.maxComponentNumber)..
            ", Edges: "..tostring(hoverMatrix:CountEdges())..
            ", Final Hover Components: "..tostring(hoverMatrix.numComponents)
        )
        WARN(
            "Initial Amph Components: "..tostring(amphMatrix.maxComponentNumber)..
            ", Edges: "..tostring(amphMatrix:CountEdges())..
            ", Final Amph Components: "..tostring(amphMatrix.numComponents)
        )
    end,

    --- Draws components.  Increment sparsity from 1 to draw less.
    ---@param self GameMap
    ---@param layer GenLayer
    ---@param sparsity number
    DrawComponents = function(self, layer, sparsity)
        ForkThread(
            function()
                coroutine.yield(50)
                while true do
                    for i = 1, self.maxi do
                        for j = 1, self.maxj do
                            if layer == LAYER_LAND then
                                self.mapAreas[i][j]:DrawLandComponents(sparsity)
                            elseif layer == LAYER_NAVY then
                                self.mapAreas[i][j]:DrawNavyComponents(sparsity)
                            elseif layer == LAYER_HOVER then
                                self.mapAreas[i][j]:DrawHoverComponents(sparsity)
                            elseif layer == LAYER_AMPH then
                                self.mapAreas[i][j]:DrawAmphComponents(sparsity)
                            end
                        end
                    end
                    WaitTicks(2)
                end
            end
        )
        
    end,

    --[[
        TODO functions:
            zone/marker generation (inc edges),
            can path to, unit can path to,
            distance from pos A to pos B (approx?),
            get layer (for a group of units),
            closest marker/zone,
            component size.
    ]]
    
})

local map = GameMap()

function OnBeginSession()
    -- TODO: Detect if a map is required (inc versioning?)
    if not PLAYABLE_AREA then
        PLAYABLE_AREA = { DEFAULT_BORDER, DEFAULT_BORDER, ScenarioInfo.size[1], ScenarioInfo.size[2] }
    end
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    -- Initialise map: do grid connections, generate components
    map:Init()
    map:DrawComponents(LAYER_LAND, 1)
    LOG(string.format('GammaAI framework: Map initialisation complete, runtime: %.2f seconds.', GetSystemTimeSecondsOnlyForProfileUse() - START ))
end

function GetMap()
    return map
end