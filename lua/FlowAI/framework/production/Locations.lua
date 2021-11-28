--[[
    Picks locations for building on
    TODOs:
        Fix build deconfliction
        Support marker finding stuff
        Support orientation in finding locations
]]

local PROFILER = import('/mods/DilliDalli/lua/FlowAI/framework/utils/Profiler.lua').GetProfiler()

local _OFFSETS = {
    -- Orientation to search in = {X, Z, {{next X, next Z, next Last}, ...}}
    negZ = { {0, -1, {{0, -1, 1}, {-1, 0, 3}, {1, 0, 2}}}, {1, 0, {{1, 0, 2}}}, {-1, 0, {{-1, 0, 3}}}, {0, 1, {{0, 1, 4}, {1, 0, 2}, {-1, 0, 3}}} },
    posZ = { {0, 1, {{0, 1, 1}, {1, 0, 3}, {-1, 0, 2}}}, {-1, 0, {{-1, 0, 2}}}, {1, 0, {{1, 0, 3}}}, {0, -1, {{0, -1, 4}, {-1, 0, 2}, {1, 0, 3}}} },
    negX = { {-1, 0, {{-1, 0, 1}, {0, -1, 3}, {1, 0, 2}}}, {0, 1, {{0, 1, 2}}}, {0, -1, {{0, -1, 3}}}, {1, 0, {{1, 0, 4}, {0, 1, 2}, {0, -1, 3}}} },
    posX = { {1, 0, {{1, 0, 1}, {0, 1, 3}, {-1, 0, 2}}}, {0, -1, {{0, -1, 2}}}, {0, 1, {{0, 1, 3}}}, {-1, 0, {{-1, 0, 4}, {0, -1, 2}, {0, 1, 3}}} },
}

-- What sorcery is this??
local _ORDER = {  3,  5,  4,  7,  8,  9,  0,  1,  2, 11,
                  6, 14, 15, 13, 17, 19, 20, 23, 24, 27,
                 -- Does the author just not know how to count??
                 29, 10, 26, 31, 34, 35, 21, 39, 41, 32,
                 44, 47, 48, 12, 43, 49, 53, 55, 25, 54,
                 -- Maybe they're just suuuuuuuper high??
                 59, 38, 51, 16, 33, 50, 18, 37, 56, 22,
                 45, 28, 57, 30, 36, 40, 42, 46, 52, 58 }

local COORDS = { negZ = { {0, 0} }, posZ = { {0, 0} }, negX = { {0, 0} }, posX = { {0, 0} } }

function InitialiseCoords()
    local START = GetSystemTimeSecondsOnlyForProfileUse()
    local sizes = { 1, 1, 1, 1 }
    for _, radius in _ORDER do
        for _, last in {1,2,3,4} do
            local resNegZ = GenerateCoords(_OFFSETS.negZ[last][1],_OFFSETS.negZ[last][2],last,_OFFSETS.negZ, radius)
            for _, coord in resNegZ do
                sizes[1] = sizes[1] + 1
                COORDS.negZ[sizes[1]] = coord
            end
            local resPosZ = GenerateCoords(_OFFSETS.posZ[last][1],_OFFSETS.posZ[last][2],last,_OFFSETS.posZ, radius)
            for _, coord in resPosZ do
                sizes[2] = sizes[2] + 1
                COORDS.posZ[sizes[2]] = coord
            end
            local resNegX = GenerateCoords(_OFFSETS.negX[last][1],_OFFSETS.negX[last][2],last,_OFFSETS.negX, radius)
            for _, coord in resNegX do
                sizes[3] = sizes[3] + 1
                COORDS.negX[sizes[3]] = coord
            end
            local resPosX = GenerateCoords(_OFFSETS.posX[last][1],_OFFSETS.posX[last][2],last,_OFFSETS.posX, radius)
            for _, coord in resPosX do
                sizes[4] = sizes[4] + 1
                COORDS.posX[sizes[4]] = coord
            end
        end
    end
    LOG(string.format('FlowAI framework: InitialiseCoords() finished, runtime: %.2f seconds.', GetSystemTimeSecondsOnlyForProfileUse() - START ))
end

function GenerateCoords(x, z, last, instructions, radius)
    if radius == 0 then
        return {{x,z}}
    end
    local coords = {}
    local coordsNext = 1
    for _, offsets in instructions[last][3] do
        local res = GenerateCoords(x+offsets[1],z+offsets[2],offsets[3], instructions, radius-1)
        for _, v in res do
            coords[coordsNext] = v
            coordsNext = coordsNext + 1
        end
    end
    return coords
end

Location = Class({
    Init = function(self,x,z,radius)
        self.x = x
        self.z = z
        self.radius = radius
    end,
})

BuildDeconfliction = Class({
    Init = function(self)
        self.pendingStructures = {}
        self.numPending = 0
        self.nextID = 1
    end,

    Register = function(self, loc, bp)
        self.numPending = self.numPending + 1
        self.pendingStructures[self.numPending] = { pos = loc, bp = bp, id = self.nextID }
        self.nextID = self.nextID + 1
        return self.nextID - 1
    end,

    Clear = function(self, id)
        local i = 1
        while i < self.numPending do
            if self.pendingStructures[i].id == id then
                self.pendingStructures[i] = self.pendingStructures[self.numPending]
                self.numPending = self.numPending - 1
                return
            end
            i = i + 1
        end
        self.numPending = self.numPending - 1
        return
    end,

    Check = function(self, loc, bp)
        -- TODO: Fix this, noticed it's not working quite right (copied this function from old BaseController, with attached warning)
        -- EDIT TODO: Can confirm this just doesn't work.
        -- Checks if any planned buildings overlap with this building.  Return true if they do not.
        local cornerX0 = loc[1]+bp.SizeX/2
        local cornerZ0 = loc[3]+bp.SizeZ/2
        local cornerX1 = loc[1]-bp.SizeX/2
        local cornerZ1 = loc[3]-bp.SizeZ/2
        local i = 1
        while i <= self.numPending do
            v = self.pendingStructures[i]
            -- If overlap, return false
            if loc[1] == v.pos[1] and loc[3] == v.pos[3] then
                -- Location is the same, return false
                return false
            elseif cornerX0 >= v.pos[1]-v.bp.SizeX/2 and cornerX0 <= v.pos[1]+v.bp.SizeX/2 and cornerZ0 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ0 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Bottom right corner
                return false
            elseif cornerX1 >= v.pos[1]-v.bp.SizeX/2 and cornerX1 <= v.pos[1]+v.bp.SizeX/2 and cornerZ0 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ0 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Bottom left corner
                return false
            elseif cornerX0 >= v.pos[1]-v.bp.SizeX/2 and cornerX0 <= v.pos[1]+v.bp.SizeX/2 and cornerZ1 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ1 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Top right corner
                return false
            elseif cornerX1 >= v.pos[1]-v.bp.SizeX/2 and cornerX1 <= v.pos[1]+v.bp.SizeX/2 and cornerZ1 >= v.pos[3]-v.bp.SizeZ/2 and cornerZ1 <= v.pos[3]+v.bp.SizeZ/2 then
                -- Top left corner
                return false
            end
            i = i + 1
        end
        return true
    end,

    FindBuildCoordinates = function(self, loc, bpID, aiBrain)
        -- No pathability checks are run here
        -- TODO: add orientation switch here
        -- TODO: some kind of overlap check with self??
        local start = PROFILER:Now()
        local bp = GetUnitBlueprintByName(bpID)
        for _, v in COORDS.negZ do
            local coords = {loc[1]+v[1], GetSurfaceHeight(loc[1]+v[1], loc[3]+v[2]), loc[3]+v[2]}
            if aiBrain:CanBuildStructureAt(bpID,coords) and self:Check(coords,bp) then
                PROFILER:Add("FindBuildCoordinates",PROFILER:Now()-start)
                return coords
            end
        end
        -- Fail to find a location
        PROFILER:Add("FindBuildCoordinates",PROFILER:Now()-start)
        return nil
    end,
})