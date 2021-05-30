BaseBuilderTemplate {
    BaseTemplateName = 'DilliDalliTemplate',
    Builders = { },
    NonCheatBuilders = { },
    BaseSettings = { },
    ExpansionFunction = function(aiBrain, location, markerType)
        -- Expanding is for casuals (and people who know how this works, which I don't...)
        return 0
    end,

    FirstBaseFunction = function(aiBrain)
        local per = ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality
        if not per then 
            return 0, 'DilliDalliTemplate'
        end
        if per != 'DilliDalliAIKey' then
            return 0, 'DilliDalliTemplate'
        else
            return 9000, 'DilliDalliTemplate'
        end
    end,
}