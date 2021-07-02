local DilliDalliBeginSession = import('/mods/DilliDalli/lua/AI/DilliDalli/Mapping.lua').BeginSession

local DilliDalliYeOldeBeginSession = BeginSession
function BeginSession()
    DilliDalliYeOldeBeginSession()
    DilliDalliBeginSession()
end
