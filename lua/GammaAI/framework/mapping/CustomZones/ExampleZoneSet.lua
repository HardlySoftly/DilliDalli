-- This file is an example of how you can add custom zones to the GammaAI mapping framework.
-- First import this class
local ZoneSet = import('/mods/DilliDalli/lua/GammaAI/framework/mapping/Zones.lua').ZoneSet

-- We'll use these too later
local GetMarkers = import("/mods/DilliDalli/lua/GammaAI/framework/mapping/Mapping.lua").GetMarkers
local MAP = import("/mods/DilliDalli/lua/GammaAI/framework/mapping/Mapping.lua").GetMap()

-- Now create a subclass of 'ZoneSet', non-destructively hooking 'Init' and implementing the 'GenerateZoneList' function.
-- You can create as many classes as you like here.
-- Don't bother implementing any other methods or having any other variables since they'll be lost in the copy operation.
ExampleZoneSet = Class(ZoneSet){
    Init = function(self,zoneIndex)
        ZoneSet.Init(self,zoneIndex)
        -- Choice of the layer you want these zones to exist in.
        self.layer = 1 -- land
        -- In your own custom classes please set this to something unique so you can identify your zones later.
        self.name = 'ExampleZoneSet'
    end,
    GenerateZoneList = function(self)
        -- Step 1: Get a set of markers that are in the layer we're currently interested in.
        local markers = {}
        for _, marker in GetMarkers() do
            if MAP:GetComponent(marker.position,self.layer) > 0 then
                table.insert(markers,marker)
            end
        end
        -- Step 2: Create zones based on markers.  Each marker is a new zone.
        for _, marker in markers do
            -- A word of warning: Be careful about what you pass into 'self:AddZone', since a deepcopy does get called on this table.
            self:AddZone({pos=marker.position})
        end
    end,
}

-- Now implement a 'GetZoneSetClasses' function to export the zones you want to include in the game.
function GetZoneSetClasses()
    -- Set to true if you want to test this
    local testingExampleZoneSet = true
    if testingExampleZoneSet then
        -- Include as many classes here as you like (and are willing to take the performance hit for).
        return {ExampleZoneSet}
    else
        return {}
    end
end

--[[
    Awesome, we've implemented and added a new set of Zones to the GammaAI mapping framework!  What
    you'll want to do now is load these into your AI so you can make use of them.

    In order to avoid problems with different AIs changing data in the same zone tables, the
    'GameMap' class implements a way of exporting a completely clean version of a ZoneSet, that you
    can use freely within a single AI without worrying about those issues.

    In order to find and export your custom zones, you'll need to call:
        'map:FindZoneSet(name,layer)'.
    
    If you have a 'zoneSet' variable, you can also ask the map what zone a thing is in using:
        'map:GetZoneID(pos,zoneSet.index)'
]]
