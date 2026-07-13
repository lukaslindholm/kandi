#TODO kolla upp hur lönar det sig att optimera bänkspelarna
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
        total_xp = objective_value(model)
        
        println("\n==================================================")
        println("OPTIMALT LAG FÖR GAMEWEEK $gw")
        println("Total förväntad poäng (xP): ", round(total_xp, digits=2))
        println("--------------------------------------------------")
        println("STARTELVA:")
        
        # Loopa igenom och skriv ut startelvan
        for i in 1:n
            if value(s[i]) > 0.5
                # Kolla om spelaren är kapten
                role = value(c[i]) > 0.5 ? "(KAPTEN)" : ""
                
                name = df_gw.name[i]
                pos = df_gw.position[i]
                
                # Vaastavs pris är t.ex. 100 för £10.0m, så vi delar med 10
                price = df_gw.now_cost[i] / 10.0 
                xp = round(df_gw.expected_points[i], digits=2)
                
                # rpad används för att skapa snygga kolumner i terminalen
                println(rpad(name, 25), rpad(pos, 5), rpad("£$price", 7), rpad("$(xp) xP", 8), role)
            end
        end
        
        println("--------------------------------------------------")
        println("BÄNK:")
        
        # Loopa igenom och skriv ut bänken
        for i in 1:n
            if value(b[i]) > 0.5
                name = df_gw.name[i]
                pos = df_gw.position[i]
                price = df_gw.now_cost[i] / 10.0
                xp = round(df_gw.expected_points[i], digits=2)
                
                println(rpad(name, 25), rpad(pos, 5), rpad("£$price", 7), rpad("$(xp) xP", 8))
            end
        end
        println("==================================================\n")
        
        push!(results, (GW = gw, ExpectedPoints = total_xp))
        # --------------------------------------------------
        # SIMULERING AV FPL AUTO-SUBS OCH FAKTISKA POÄNG
        # --------------------------------------------------
        
        # 1. Identifiera spelarnas index i DataFramen
        starters_idx = Int[]
        bench_idx = Int[]
        captain_idx = 0
        
        for i in 1:n
            if value(s[i]) > 0.5
                push!(starters_idx, i)
                if value(c[i]) > 0.5
                    captain_idx = i
                end
            elseif value(b[i]) > 0.5
                push!(bench_idx, i)
            end
        end
        
        # 2. Sortera bänken i rätt ordning (störst xP först)
        bench_gk = filter(i -> df_gw.position[i] == "GK", bench_idx)
        bench_outfield = filter(i -> df_gw.position[i] != "GK", bench_idx)
        sort!(bench_outfield, by = i -> df_gw.expected_points[i], rev=true)
        
        # 3. Genomför auto-subs
        # Målvakt
        gk_idx_in_array = findfirst(i -> df_gw.position[i] == "GK", starters_idx)
        gk_in_df = starters_idx[gk_idx_in_array]
        
        if df_gw.minutes[gk_in_df] == 0 && !isempty(bench_gk)
            bgk = bench_gk[1]
            if df_gw.minutes[bgk] > 0
                starters_idx[gk_idx_in_array] = bgk
                println("-> BYTE: ", df_gw.name[bgk], " (GK) in för ", df_gw.name[gk_in_df])
            end
        end
        
        # Utespelare (Håll koll på formationen så vi inte får t.ex. 2 backar)
        formation = Dict(
            "DEF" => sum(df_gw.position[i] == "DEF" for i in starters_idx),
            "MID" => sum(df_gw.position[i] == "MID" for i in starters_idx),
            "FWD" => sum(df_gw.position[i] == "FWD" for i in starters_idx)
        )
        
        for (s_i, p_idx) in enumerate(starters_idx)
            if df_gw.position[p_idx] != "GK" && df_gw.minutes[p_idx] == 0
                # Spelaren spelade 0 minuter, sök efter bästa möjliga ersättare
                for (b_i, sub_idx) in enumerate(bench_outfield)
                    if sub_idx == -1 
                        continue # Denna spelare har redan bytts in
                    end
                    
                    if df_gw.minutes[sub_idx] > 0
                        pos_out = df_gw.position[p_idx]
                        pos_in = df_gw.position[sub_idx]
                        
                        # Kontrollera att bytet inte bryter mot minimum-kraven
                        if pos_out != pos_in
                            if pos_out == "DEF" && formation["DEF"] <= 3
                                continue # Kan inte ta ut en back, vi måste ha minst 3
                            end
                            if pos_out == "FWD" && formation["FWD"] <= 1
                                continue # Kan inte ta ut en anfallare, vi måste ha minst 1
                            end
                            # Uppdatera formationen om bytet godkänns
                            formation[pos_out] -= 1
                            formation[pos_in] += 1
                        end
                        
                        # Gör bytet!
                        starters_idx[s_i] = sub_idx
                        bench_outfield[b_i] = -1 # Markera bänkspelaren som använd
                        println("-> BYTE: ", df_gw.name[sub_idx], " in för ", df_gw.name[p_idx])
                        break
                    end
                end
            end
        end
        
        # 4. Hantera Vicekapten
        # Om originalkaptenen har 0 minuter, flyttas bindeln
        if df_gw.minutes[captain_idx] == 0
            # Hitta de spelare i den nya startelvan som faktiskt har spelat
            played_starters = filter(i -> df_gw.minutes[i] > 0, starters_idx)
            if !isempty(played_starters)
                # Vi ger bindeln till den som hade högst xP (bland de som spelade)
                captain_idx = argmax(i -> df_gw.expected_points[i], played_starters)
                println("-> KAPTENSBYTE (Vice): ", df_gw.name[captain_idx], " tar över bindeln.")
            end
        end
        
        # 5. Räkna ut faktiska poäng
        actual_points = 0
        for i in starters_idx
            pts = df_gw.total_points[i]
            actual_points += pts
            if i == captain_idx
                actual_points += pts # Dubbla poäng för kaptenen
            end
        end
        
        println("--------------------------------------------------")
        println("FAKTISKA POÄNG (inkl. byten/kapten): ", actual_points)
        println("==================================================\n")
    else
        println("Kunde inte hitta en optimal lösning för GW $gw")
    end
end

println("Alla omgångar analyserade!")