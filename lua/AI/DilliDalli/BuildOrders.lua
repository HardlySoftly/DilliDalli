LandHydroLand = {
    mobile = {
        { work="LandFactoryT1", priority=4, location=nil, distance=0, targetSpend=2, buildOrder=true, count=1, duplicates=1, keep=false },
        { work="MexT1", priority=3, location=nil, distance=0, targetSpend=2, buildOrder=true, count=3, duplicates=2, keep=false },
        { work="Hydro", priority=2, location=nil, distance=0, targetSpend=100, buildOrder=true, count=1, duplicates=1, keep=false },
        { work="LandFactoryT1", priority=1, location=nil, distance=0, targetSpend=2, buildOrder=true, count=1, duplicates=1, keep=false },
    },
    factory = {
        { work="EngineerT1", priority=1, location=nil, distance=0, targetSpend=10, buildOrder=true, count=6, duplicates=1, keep=false },
    }
}

LandLand = {
    mobile = {
        { work="LandFactoryT1", priority=5, location=nil, distance=0, targetSpend=20, buildOrder=true, count=1, duplicates=1, keep=false, com=true, assist=false },
        { work="PgenT1", priority=4, location=nil, distance=0, targetSpend=20, buildOrder=true, count=2, duplicates=1, keep=false, com=true, assist=false },
        { work="MexT1", priority=3, location=nil, distance=0, targetSpend=20, buildOrder=true, count=4, duplicates=3, keep=false, assist=false },
        { work="PgenT1", priority=2, location=nil, distance=0, targetSpend=20, buildOrder=true, count=3, duplicates=2, keep=false, com=true, assist=false },
        { work="LandFactoryT1", priority=1, location=nil, distance=0, targetSpend=10, buildOrder=true, count=1, duplicates=1, keep=false, com=true, assist=true },
    },
    factory = {
        { work="EngineerT1", priority=2, location=nil, distance=0, targetSpend=20, buildOrder=true, count=3, duplicates=1, keep=false, assist=false },
        { work="DirectFireT1", priority=1, location=nil, distance=0, targetSpend=20, buildOrder=true, count=2, duplicates=1, keep=false, assist=false },
    }
}