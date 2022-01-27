local GetMarkers = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMarkers
local MAP = import("/mods/DilliDalli/lua/FlowAI/framework/mapping/Mapping.lua").GetMap()
local CreatePriorityQueue = import('/mods/DilliDalli/lua/FlowAI/framework/utils/PriorityQueue.lua').CreatePriorityQueue

ZoneSet = Class({
    Init = function(self,zoneIndex)
        self.zones = {}
        self.edges = nil
        self.distances = nil
        self.numZones = 0
        self.index = zoneIndex
    end,

    AddZone = function(self,zone)
        -- The zone you're adding can have custom fields within reason - we're calling a table.deepcopy on it later.
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
            table.insert(self:GetZone(edge.zones[1]).edges,{zone = self:GetZone(edge.zones[2]), border=edge.border, distance=edge.distance, midpoint=table.copy(edge.midpoint)})
            table.insert(self:GetZone(edge.zones[2]).edges,{zone = self:GetZone(edge.zones[1]), border=edge.border, distance=edge.distance, midpoint=table.copy(edge.midpoint)})
        end
        self:InitDistances()
    end,

    InitDistances = function(self)
        -- Fill out a zone distance matrix so that zone to zone distances can be easily fetched later.
        if self.numZones > 1000 then
            WARN("The total number of zones is getting kinda high ("..tostring(self.numZones).."), you may experience some performance impacts :(")
        end
        self.distances = {}
        for i=1, self.numZones do
            self.distances[i] = {}
            for j=1, self.numZones do
                if i == j then
                    self.distances[i][j] = 0
                else
                    self.distances[i][j] = -1
                end
            end
        end
        local pq = CreatePriorityQueue()
        -- Avoid duplicating work by requiring source ID < destination ID
        for i=1, self.numZones do
            for _, edge in self.zones[i].edges do
                if self.zones[i].id < edge.zone.id then
                    pq:Queue({source = self.zones[i].id, destination = edge.zone.id, priority = edge.distance})
                end
            end
        end
        -- Don't you just love priority queues?
        while pq:Size() > 0 do
            local item = pq:Dequeue()
            if (self.distances[item.source][item.destination] < 0) or (item.priority < self.distances[item.source][item.destination]) then
                self.distances[item.source][item.destination] = item.priority
                self.distances[item.destination][item.source] = item.priority
                for _, edge in self.zones[item.source].edges do
                    if (edge.zone.id < item.destination) and (self.distances[edge.zone.id][item.destination] < 0) then
                        pq:Queue({source = edge.zone.id, destination = item.destination, priority = item.priority + edge.distance})
                    end
                end
                for _, edge in self.zones[item.destination].edges do
                    if (item.source < edge.zone.id) and (self.distances[item.source][edge.zone.id] < 0) then
                        pq:Queue({source = item.source, destination = edge.zone.id, priority = item.priority + edge.distance})
                    end
                end
            end
        end
    end,

    GetDistance = function(self,id0,id1)
        -- Get the graph distance between two zones - i.e. travelling only along edges between two zones how close are they?
        -- Pass in zone ids, get out the distance.  A distance of -1 implies you can't get between the two zones.
        -- GetDistance(a,b) is always equal to GetDistance(b,a)
        return self.distances[id0][id1]
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
            if zone.fail then
                continue
            end
            DrawCircle(zone.pos,10,'aaffffff')
            for _, edge in zone.edges do
                -- Only draw each edge once
                if zone.id < edge.zone.id then
                    DrawLine(zone.pos,edge.midpoint,'aa000000')
                    DrawLine(edge.midpoint,edge.zone.pos,'aa000000')
                end
            end
        end
    end,
})

function LoadCustomZoneSets()
    local res = {}
    local simMods = __active_mods or {}
    --for _, ModData in simMods do
    --local customZoneSetFiles = DiskFindFiles(ModData.location..'/lua/FlowAI/framework/mapping/CustomZones', '*.lua')
    local customZoneSetFiles = DiskFindFiles('/mods/DilliDalli/lua/FlowAI/framework/mapping/CustomZones', '*.lua')
    for _, file in customZoneSetFiles do
        local GetZoneSetClasses = import(file).GetZoneSetClasses
        if GetZoneSetClasses then
            local zoneSetClasses = GetZoneSetClasses()
            for _, ZoneSetClass in zoneSetClasses do
                table.insert(res,ZoneSetClass)
            end
        end
    end
    --end
    return res
end
