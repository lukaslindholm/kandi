using DataFrames, CSV
using JuMP, Gurobi

# Skapa en tom lista för att spara resultaten från alla omgångar
results = []

println("Startar optimering av alla Gameweeks...")

for gw in 1:38
    filnamn = "clean_data/gw$(gw)_ready.csv"
    
    # Kolla om filen existerar (om omgången t.ex. blev inställd eller saknar data)
    if !isfile(filnamn)
        println("Hoppar över GW $gw - fil saknas.")
        continue
    end
    
    df_gw = CSV.read(filnamn, DataFrame)
    n = nrow(df_gw)
    
    # Skapa modellen
    model = Model(Gurobi.Optimizer)
    set_silent(model) # Stänger av Gurobis utskrifter i terminalen för att hålla det rent
    
    # Beslutsvariabler
    @variable(model, s[1:n], Bin) # Startelva
    @variable(model, b[1:n], Bin) # Bänk
    @variable(model, c[1:n], Bin) # Kapten
    
    # Målfunktion (Maximera xP)
    @objective(model, Max, sum(df_gw.expected_points[i] * (s[i] + c[i]) for i in 1:n))
    
    # Bivillkor: Logik och Truppstorlek
    for i in 1:n
        @constraint(model, s[i] + b[i] <= 1)
        @constraint(model, c[i] <= s[i])
    end
    @constraint(model, sum(s) == 11)
    @constraint(model, sum(b) == 4)
    @constraint(model, sum(c) == 1)
    
    # Bivillkor: Budget
    @constraint(model, sum(df_gw.now_cost[i] * (s[i] + b[i]) for i in 1:n) <= 1000)
    
    # Bivillkor: Max 3 från samma lag
    teams = unique(df_gw.team)
    for team in teams
        @constraint(model, sum((s[i] + b[i]) for i in 1:n if df_gw.team[i] == team) <= 3)
    end
    
    # Bivillkor: Positionskrav (Total trupp)
    @constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.position[i] == "GK") == 2)
    @constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.position[i] == "DEF") == 5)
    @constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.position[i] == "MID") == 5)
    @constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.position[i] == "FWD") == 3)
    
    # Bivillkor: Positionskrav (Startelvan: Minst 1 GK, 3 Backar, 1 Anfallare)
    @constraint(model, sum(s[i] for i in 1:n if df_gw.position[i] == "GK") == 1)
    @constraint(model, sum(s[i] for i in 1:n if df_gw.position[i] == "DEF") >= 3)
    @constraint(model, sum(s[i] for i in 1:n if df_gw.position[i] == "FWD") >= 1)
    
    # Kör optimeringen
    optimize!(model)
    
    # Kontrollera om en lösning hittades
    if termination_status(model) == MOI.OPTIMAL
        # Beräkna total förväntad poäng och total FAKTISK poäng för utvärderingen
        total_xp = objective_value(model)
        
        # Plocka ut det optimerade laget
        team_selected = []
        for i in 1:n
            if value(s[i]) > 0.5
                push!(team_selected, df_gw.name[i])
            end
        end
        
        push!(results, (GW = gw, ExpectedPoints = total_xp))
        println("GW $gw löst! Total xP: ", round(total_xp, digits=2))
    else
        println("Kunde inte hitta en optimal lösning för GW $gw")
    end
end

println("Alla omgångar analyserade!")