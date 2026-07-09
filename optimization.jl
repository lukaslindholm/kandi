using DataFrames, CSV
using JuMP, Gurobi

# 1. Läs in hela CSV-filen
df = CSV.read("fpl-data-stats.csv", DataFrame)

# 2. Filtrera fram data för endast en omgång (t.ex. Gameweek 1)
gw_target = 1
df_gw = subset(df, :gameweek => x -> x .== gw_target)

# Antal spelare i den filtrerade datan
n = nrow(df_gw)

# 3. Skapa modellen och koppla den till Gurobi
model = Model(Gurobi.Optimizer)

# 4. Skapa beslutsvariabler
@variable(model, s[1:n], Bin) # Spelaren startar (11 st)
@variable(model, b[1:n], Bin) # Spelaren sitter på bänken (4 st)
@variable(model, c[1:n], Bin) # Spelaren är kapten (1 st)

# 5. Målfunktion
@objective(model, Max, sum(df_gw.expected_points[i] * (s[i] + c[i]) for i in 1:n))

# A. Logiska begränsningar per spelare
for i in 1:n
    # En spelare kan max ha en roll (antingen start eller bänk, eller inget)
    @constraint(model, s[i] + b[i] <= 1)
    
    # Kaptenen måste finnas i startelvan
    @constraint(model, c[i] <= s[i])
end

# B. Truppstorlek
@constraint(model, sum(s) == 11) # Exakt 11 startar
@constraint(model, sum(b) == 4)  # Exakt 4 på bänken
@constraint(model, sum(c) == 1)  # Exakt 1 kapten

# C. Budget
@constraint(model, sum(df_gw.now_cost[i] * (s[i] + b[i]) for i in 1:n) <= 100)

# D. Max 3 spelare från samma lag
teams = unique(df_gw.team_name)
for team in teams
    @constraint(model, sum((s[i] + b[i]) for i in 1:n if df_gw.team_name[i] == team) <= 3)
end

# E. Positionskrav (Total trupp)
# 1=Målvakt, 2=Back, 3=Mittfältare, 4=Anfallare
@constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.element_type[i] == 1) == 2)
@constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.element_type[i] == 2) == 5)
@constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.element_type[i] == 3) == 5)
@constraint(model, sum(s[i] + b[i] for i in 1:n if df_gw.element_type[i] == 4) == 3)

# F. Positionskrav (Startelvan: Minst 1 GK, 3 Backar, 1 Anfallare)
@constraint(model, sum(s[i] for i in 1:n if df_gw.element_type[i] == 1) == 1)
@constraint(model, sum(s[i] for i in 1:n if df_gw.element_type[i] == 2) >= 3)
@constraint(model, sum(s[i] for i in 1:n if df_gw.element_type[i] == 4) >= 1)

# 6. Optimera!
optimize!(model)

# 7. Plocka ut det vinnande laget
println("Total förväntad poäng (xP): ", objective_value(model))

# Gå igenom resultatet och skriv ut vilka spelare som valdes
println("\nSTARTELVA:")
for i in 1:n
    if value(s[i]) > 0.5
        role = value(c[i]) > 0.5 ? "(KAPTEN)" : ""
        println(df_gw.web_name[i], " - ", df_gw.expected_points[i], " xP ", role)
    end
end

println("\nBÄNK:")
for i in 1:n
    if value(b[i]) > 0.5
        println(df_gw.web_name[i])
    end
end