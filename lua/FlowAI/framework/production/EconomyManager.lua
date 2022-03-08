local function GetMassPriority(template, marginalEnergyCost, safety)
    -- Formula for calculating the relative priority of building some mass producing thing.
    --[[
        So what does this formula mean, and how did we get to it?
        Firstly, to explain the arguments:
            - production (template.production) - the amount of mass the 'thing' will produce per second once it is constructed.
            - cost (template.cost) - the amount of mass the 'thing' costs directly to build.
            - maintenance (template.maintenance) - the amount of energy the 'thing' will cost to run (without which no mass is produced).
            - marginalEnergyCost - the current expected mass cost of getting +1 additional power generation capacity.
            - safety - the expected half life of the 'thing' in seconds (i.e. time by which we estimate it has a 50% chance of being destroyed).

        The simplest version of this formula would be:
            production / cost
        i.e. per unit mass spent, how much production can we get.

        Unfortunately, this doesn't account for the ongoing associated energy costs, which can be really high for things like mass fabricators!
        Here though we can exploit that fact that power generators don't come with an ongoing mass cost, and so we can get a much better estimate for
        actual costs by including the mass cost of the pgens we build to help run the 'thing'.  This changes through the game (t3 pgens are much more
        mass efficient per unit power produced than t1 pgens for example), and so we get the AI to tell us how much a unit of energy costs.

        Our AI can find this out using a simple forumla:
            marginalEnergyCost = massCostOfPgen / energyProducedByPgen
        This needs to be calculated for each pgen, with the lowest marginalEnergyCost indicating the best pgen (subject to tech level availability).

        So our updated cost estimate is:
            actualCost = cost + maintenance * marginalEnergyCost
        Giving a formula of:
            production / (cost + maintenance * marginalEnergyCost)

        This is an improvement, but it still misses something, namely that the enemy will try to blow your buildings up.  Mass points further away
        from your base are more vulnerable, and intuitively we know this means we should upgrade them later than safer mass extractors.  The key
        thing we're estimating as humans can be summed up with the 'saftey' parameter - which gives an estimate of how long until a thing is lost.

        For simplicity, we assume that the probability of losing the 'thing' we build is constant (which we don't actually know, but estimating the
        chance of losing something to a greater degree of precision is excessively hard), and so the chance of losing it on any given second is:
            probabilityOfDestructionPerSecond = math.pow(0.5,1/safety)

        How do we use that to influence our priority?  Well, if a 'thing' is lost, then the natural action to take is to rebuild it.  We calculated
        the 'actualCost' earlier, and so we can use that to generate a per second estimate of the resources spent rebuilding the 'thing':
            perSecondRebuildCost = probabilityOfDestructionPerSecond * actualCost

        This 'perSecondRebuildCost' is like negative production; it's a thing we have to spend to maintain 'production' of mass per second.  This
        means our net mass per second from building the 'thing' is more like:
            netProduction = production - perSecondRebuildCost

        So our improved estimate is now:
            priority = netProduction / actualCost
                     = (production - perSecondRebuildCost) / actualCost
                     = (production - probabilityOfDestructionPerSecond * actualCost) / actualCost
                     = (production / actualCost) - probabilityOfDestructionPerSecond
                     = (production / (cost + maintenance * marginalEnergyCost)) - (1 - math.pow(0.5,1/safety))
                     = production / (cost + maintenance * marginalEnergyCost) - 1 + math.pow(0.5,1/safety)
    ]]
    return template.production / (template.cost + template.maintenance * marginalEnergyCost) - 1 + math.pow(0.5, 1 / safety)
end

local function GetEnergyPriority(template, safety)
    -- Formula for calculating the relative priority of building some mass producing thing.
    -- See mass version for explanation; energy case is simpler since there isn't any maintenance required to run pgens.
    return template.production / template.cost - 1 + math.pow(0.5, 1 / safety)
end
