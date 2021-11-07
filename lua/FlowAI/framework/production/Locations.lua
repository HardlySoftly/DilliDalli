--[[
    Picks locations for building on
]]

Deconflicter = Class({
    Init = function(self)
        self.pendingStructures = {}
        self.numPending = 0
    end,

    Register = function(self, loc, bp)
        self.numPending = self.numPending + 1
        self.pendingStructures[self.numPending] = { pos = loc, bp = bp }
    end,

    Clear = function(self, loc)
        local i = 1
        while i < self.numPending do
            if (self.pendingStructures[i].pos[1] == loc[1]) and (self.pendingStructures[i].pos[3] == loc[3]) then
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
        -- Checks if any planned buildings overlap with this building.  Return true if they do not.
        local cornerX0 = location[1]+bp.SizeX/2
        local cornerZ0 = location[3]+bp.SizeZ/2
        local cornerX1 = location[1]-bp.SizeX/2
        local cornerZ1 = location[3]-bp.SizeZ/2
        local i = 1
        while i <= self.numPending do
            v = self.pendingStructures[i]
            -- If overlap, return false
            if location[1] == v.pos[1] and location[3] == v.pos[3] then
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
    end
})
