local GetMarkers = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMarkers
local MAP = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMap()

ZoneSet = Class({
    Init = function(self,zoneIndex)
        self.zones = {}
        self.edges = nil
        self.numZones = 0
        self.index = zoneIndex
    end,

    AddZone = function(self,zone)
        -- The zone you're adding can have custom fields within reason - we're callign a table.deepcopy on it later.
        -- Only required field is pos, and don't include id, or edges.
        self.numZones = self.numZones + 1
        zone.id = self.numZones
        zone.edges = {}
        self.zones[self.numZones] = zone
        return zone.id
    end,

    AddEdges = function(self,edges)
        -- Add the edge information from the map.  DO NOT INIT EDGES YET.
        -- We only initialise edges (involving adding reference loops) after we deepcopy the datastructure for the AI that wants it.
        self.edges = edges
    end,

    InitEdges = function(self,edges)
        -- Initialise edge references from the edge table provided by the map.
        for _, edge in edges do
            table.insert(self:GetZone(edge.zones[1]).edges,{zone = self:GetZone(edge.zones[2]), border=edge.border, distance=edge.distance})
            table.insert(self:GetZone(edge.zones[2]).edges,{zone = self:GetZone(edge.zones[1]), border=edge.border, distance=edge.distance})
        end
    end,

    GetZone = function(self,id)
        return self.zones[id]
    end,

    GetZones = function(self)
        return self.zones
    end,

    GetCopy = function(self)
        -- Get a copy of this class.  Each AI brain can have it's own set of zones without interfering with each other.
        -- DO NOT CALL THIS YOURSELF UNLESS YOU WANT THINGS TO GO HORRIBLY WRONG.
        local res = ZoneSet()
        res.index = self.index
        res.numZones = self.numZones
        res.name = self.name
        res.layer = self.layer
        -- Have to be a bit careful with what we put in zones on startup, you're risking an expensive operation here otherwise.
        -- Also this is where the deepcopy will break you if you didn't heed the warning at the top.
        res.zones = table.deepcopy(self.zones)
        res:InitEdges(self.edges)
        return res
    end,

    DrawZones = function(self)
        for _, zone in self.zones do
            DrawCircle(zone.pos,10,'aaffffff')
            for _, edge in zone.edges do
                -- Only draw each edge once
                if zone.id < edge.zone.id then
                    DrawLine(zone.pos,edge.zone.pos,'aa000000')
                end
            end
        end
    end,
})

LayerZoneSet = Class(ZoneSet){
    Init = function(self,zoneIndex)
        ZoneSet.Init(self,zoneIndex)
        -- You can't copy this class directly and expect it to work.  It implicitely expects self.index to be the layer it is operating in.
        -- To get your own version working you must change the layer here to what you want.
        self.layer = self.index
        -- In your own custom classes please set this to something unique so you can identify your zones later.
        self.name = 'LayerZoneSet'
    end,
    GenerateZoneList = function(self)
        -- Step 1: Get a set of markers that are pathable from the layer we're currently interested in.
        local markers = {}
        for _, marker in GetMarkers() do
            if MAP:GetComponent(marker.position,self.layer) > 0 then
                table.insert(markers,marker)
            end
        end
        -- Step 2: Group these and initialise zones.
        -- TODO: actually do some grouping
        for _, marker in markers do
            self:AddZone({pos=marker.position})
        end
    end,
}

function LoadCustomZoneSets()
    local res = {}
    local simMods = __active_mods or {}
    for _, ModData in simMods do
        local customZoneSetFiles = DiskFindFiles(ModData.location..'/lua/FlowAI/framework/mapping/CustomZones', '*.lua')
        for _, file in customZoneSetFiles do
            local GetZoneSetClasses = import(file).GetZoneSetClasses
            if GetZoneSetClasses then
                local zoneSetClasses = GetZoneSetClasses()
                for _, ZoneSetClass in zoneSetClasses do
                    table.insert(res,ZoneSetClass)
                end
            end
        end
    end
    return res
end
