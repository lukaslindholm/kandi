import pandas as pd

# 1. Inställningar
säsong = "2025-26" # Använder säsongen från dina länkar
antal_gws = 38
output_mapp = "./clean_data/" # Se till att denna mapp existerar där du kör skriptet

# 2. Ladda ner Vaastavs merged_gw.csv för hela säsongen
print("Laddar ner Vaastavs merged_gw.csv...")
vaastav_url = f"https://raw.githubusercontent.com/vaastav/Fantasy-Premier-League/refs/heads/master/data/{säsong}/gws/merged_gw.csv"
df_vaastav = pd.read_csv(vaastav_url)

# För säkerhets skull: om priset ('value') är angivet som t.ex. 100 istället för 10.0
# kan du behålla det så, men det är bra att vara medveten om det i Julia-koden.

# 3. Huvudloopen: Gå igenom alla 38 omgångar
for gw in range(1, antal_gws + 1):
    print(f"Bearbetar Gameweek {gw}...")
    
    # Filtrera Vaastavs data för endast den aktuella omgången
    df_gw_vaastav = df_vaastav[df_vaastav['GW'] == gw].copy()
    
    if df_gw_vaastav.empty:
        print(f"  Info: Ingen data hittades för GW {gw} i Vaastavs fil ännu. Hoppar över.")
        continue
    
    # URL till Sertalps projiceringar
    sertalp_url = f"https://raw.githubusercontent.com/sertalpbilal/fpl_optimized/engine/src/static/projection/{säsong}/gw{gw}.csv"
    
    try:
        # Ladda ner Sertalps data
        df_sertalp = pd.read_csv(sertalp_url)
        
        # Säkerställ att ID finns i Sertalps data
        if 'ID' not in df_sertalp.columns:
            print(f"  Varning: Hittade inte 'ID' i Sertalps gw{gw}.csv. Hoppar över.")
            continue
            
        # Den exakta kolumnen för förväntade poäng just denna vecka (t.ex. "1_Pts")
        xp_kolumn = f"{gw}_Pts"
        
        if xp_kolumn in df_sertalp.columns:
            # Plocka enbart ut ID och de förväntade poängen
            df_target_xp = df_sertalp[['ID', xp_kolumn]].copy()
            
            # Byt namn på poängkolumnen för att hålla det standardiserat för Julia
            df_target_xp = df_target_xp.rename(columns={xp_kolumn: 'expected_points'})
            
            # 4. Slå ihop Vaastav och Sertalp
            # Vaastav använder 'element' som ID, Sertalp använder 'ID'. Vi matchar dessa!
            df_final = pd.merge(
                df_gw_vaastav, 
                df_target_xp, 
                left_on='element', 
                right_on='ID', 
                how='inner'
            )
            
            # (Valfritt) Välj ut de kolumner som Julia faktiskt behöver, så datan blir lättläst
            kolumner_att_spara = [
                'element', 'name', 'position', 'team', 'value', 'expected_points', 'total_points'
            ]
            
            # Säkerställ att alla valda kolumner existerar i vår nya df
            befintliga_kolumner = [col for col in kolumner_att_spara if col in df_final.columns]
            df_final = df_final[befintliga_kolumner]
            
            # Byt namn på 'element' till 'id' och 'value' till 'now_cost' för tydlighet i Julia
            df_final = df_final.rename(columns={'element': 'id', 'value': 'now_cost'})
            
            # 5. Spara datan i din output-mapp
            filnamn = f"{output_mapp}gw{gw}_ready.csv"
            df_final.to_csv(filnamn, index=False)
            print(f"  Sparade {filnamn} framgångsrikt (Antal spelare: {len(df_final)})")
            
        else:
            print(f"  Varning: Hittade inte kolumnen {xp_kolumn} i Sertalps gw{gw}.csv.")
            
    except Exception as e:
        print(f"  Ett fel uppstod vid hämtning/bearbetning av Sertalps data för GW {gw}: {e}")

print("Sammanfogningen är färdig!")