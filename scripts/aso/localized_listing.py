#!/usr/bin/env python3
"""Write the localized App Store listing into fastlane/metadata/<locale>/.

One source of truth for every non-English locale: name, subtitle, keywords,
promotional text and a localized description. URLs are copied from en-US.
English variants (en-AU, en-CA, en-GB) copy en-US outright.

    python3 scripts/aso/localized_listing.py          # write files
    python3 scripts/aso/localized_listing.py --check  # limits only

Keywords leave out words already in the name or subtitle (Apple indexes
those) and never use league or team trademarks.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
META = ROOT / "fastlane" / "metadata"
BRAND = "Hardwood StatScout"

PRIVACY = "https://jackwallner.github.io/basketball/privacy-policy.html"
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

# Each description is built from these parts so the links and structure stay
# identical everywhere: hook, intro, free heading + bullets, plus heading +
# bullets, privacy line, subscription terms, link labels, disclaimer.
L: dict[str, dict] = {}

L["de-DE"] = dict(
    name="Basketball: " + BRAND,
    subtitle="NBA-Statistiken & Analysen",
    keywords="perzentil,wurfquote,vergleich,spieler,rangliste,ergebnisse,tabelle,boxscore,teams,live",
    promo="Gratis: Live-Ergebnisse, Boxscores, Tabellen und Perzentil-Ranglisten für jeden NBA-Spieler. StatScout+ bringt Trends, aktuelle Form und direkte Vergleiche.",
    hook="Erkenne, wer jenseits des Boxscores wirklich führt.",
    intro="StatScout misst jeden NBA-Spieler an seiner eigenen Positionsgruppe, mit den Zahlen, die Analysten nutzen: True Shooting, Usage, Wurfzonen, Spielaufbau, Rebounds, Defense und Einfluss auf dem Feld. Jede Metrik ist ein Perzentil-Balken, so fallen Elite und Schwächen sofort auf.",
    free="GRATIS",
    free_items=["Live-Ergebnisse, Boxscores und Tabellen", "Perzentil-Ranglisten für Guards, Forwards und Center", "Vollständige Spielerprofile mit erweiterten und klassischen Werten", "Folge deinem Team und deinen Lieblingsspielern"],
    plus_items=["Trends: die ganze Liga sortiert danach, wer heiß läuft oder abkühlt", "Aktuelle Form über die letzte Woche, 2 oder 4 Wochen", "Direkte Spielervergleiche und Entwicklung von Jahr zu Jahr", "Spielerbewertungen in jedem Boxscore", "Jede Saison zurück bis 2002-03"],
    privacy_line="Kein Konto, keine Werbung, kein Tracking.",
    terms="StatScout+ gibt es monatlich oder jährlich (beide mit 7 Tagen gratis) oder als einmaligen Lifetime-Kauf. Die Zahlung erfolgt über deine Apple-ID. Abos verlängern sich automatisch, wenn sie nicht mindestens 24 Stunden vor Ende des Zeitraums gekündigt werden; verwalte sie in den Einstellungen deiner Apple-ID.",
    privacy_label="Datenschutz", terms_label="Nutzungsbedingungen (EULA)",
    disclaimer="Nicht mit der NBA oder ihren Teams verbunden oder von ihnen unterstützt.",
)

L["fr-FR"] = dict(
    name="Basket: " + BRAND,
    subtitle="Stats NBA avancées & analyses",
    keywords="basketball,percentile,joueurs,comparer,classement,scores,direct,feuille de match,équipes",
    promo="Gratuit : scores en direct, feuilles de match, classements et percentiles pour chaque joueur NBA. StatScout+ ajoute les Tendances, la forme récente et les duels.",
    hook="Voyez qui domine au-delà de la feuille de match.",
    intro="StatScout classe chaque joueur NBA face à son propre groupe de postes, avec les chiffres des analystes : true shooting, usage, zones de tir, création, rebonds, défense et impact sur le terrain. Chaque statistique est une barre de percentile : l'élite et les joueurs en difficulté sautent aux yeux.",
    free="GRATUIT",
    free_items=["Scores en direct, feuilles de match et classements", "Classements en percentiles pour meneurs, ailiers et pivots", "Profils complets avec stats avancées et classiques", "Suivez votre équipe et vos joueurs favoris"],
    plus_items=["Tendances : toute la ligue classée selon qui monte ou qui baisse", "Forme récente sur la dernière semaine, 2 ou 4 semaines", "Duels entre joueurs et évolution d'une saison à l'autre", "Notes des joueurs dans chaque feuille de match", "Toutes les saisons depuis 2002-03"],
    privacy_line="Sans compte, sans publicité, sans pistage.",
    terms="StatScout+ est proposé au mois ou à l'année (avec 7 jours d'essai gratuit) ou en achat unique à vie. Le paiement est débité sur votre identifiant Apple. L'abonnement se renouvelle automatiquement sauf résiliation au moins 24 heures avant la fin de la période en cours ; gérez-le dans les réglages de votre identifiant Apple.",
    privacy_label="Confidentialité", terms_label="Conditions d'utilisation (EULA)",
    disclaimer="Non affilié à la NBA ni à ses équipes, ni approuvé par elles.",
)
L["fr-CA"] = dict(L["fr-FR"])

L["es-ES"] = dict(
    name="Baloncesto: " + BRAND,
    subtitle="Estadísticas avanzadas NBA",
    keywords="basket,percentil,jugadores,comparar,clasificación,resultados,directo,box score,equipos",
    promo="Gratis: resultados en directo, box scores, clasificaciones y percentiles de cada jugador de la NBA. StatScout+ suma Tendencias, forma reciente y duelos cara a cara.",
    hook="Descubre quién manda más allá del box score.",
    intro="StatScout compara a cada jugador de la NBA con su propio grupo de posición usando los números de los analistas: true shooting, uso, zonas de tiro, creación, rebote, defensa e impacto en pista. Cada métrica es una barra de percentil, así la élite y los que sufren se ven al instante.",
    free="GRATIS",
    free_items=["Resultados en directo, box scores y clasificaciones", "Rankings por percentil para bases, aleros y pívots", "Perfiles completos con estadísticas avanzadas y clásicas", "Sigue a tu equipo y a tus jugadores favoritos"],
    plus_items=["Tendencias: toda la liga ordenada por quién está en racha o a la baja", "Forma reciente de la última semana, 2 o 4 semanas", "Duelos entre jugadores y evolución año a año", "Valoración de cada jugador en cada box score", "Todas las temporadas desde 2002-03"],
    privacy_line="Sin cuenta, sin anuncios, sin rastreo.",
    terms="StatScout+ se ofrece mensual o anual (ambos con 7 días de prueba gratis) o como compra única de por vida. El pago se carga a tu Apple ID. La suscripción se renueva automáticamente salvo que se cancele al menos 24 horas antes del final del periodo; gestiónala en los ajustes de tu Apple ID.",
    privacy_label="Privacidad", terms_label="Condiciones de uso (EULA)",
    disclaimer="Sin afiliación ni respaldo de la NBA ni de sus equipos.",
)
L["es-MX"] = dict(L["es-ES"], name="Básquetbol: " + BRAND,
    keywords="basquet,baloncesto,percentil,jugadores,comparar,tabla,marcadores,en vivo,box score",
    promo="Gratis: marcadores en vivo, box scores, tablas y percentiles de cada jugador de la NBA. StatScout+ suma Tendencias, forma reciente y duelos cara a cara.",
    free_items=["Marcadores en vivo, box scores y tablas", "Rankings por percentil para bases, aleros y pívots", "Perfiles completos con estadísticas avanzadas y clásicas", "Sigue a tu equipo y a tus jugadores favoritos"],
    intro="StatScout compara a cada jugador de la NBA con su propio grupo de posición usando los números de los analistas: true shooting, uso, zonas de tiro, creación, rebote, defensa e impacto en la cancha. Cada métrica es una barra de percentil, así la élite y los que batallan se ven al instante.",
)

L["it"] = dict(
    name="Basket: " + BRAND,
    subtitle="Statistiche NBA avanzate",
    keywords="basketball,pallacanestro,percentile,giocatori,confronto,classifica,risultati,live,tabellino",
    promo="Gratis: risultati live, tabellini, classifiche e percentili per ogni giocatore NBA. StatScout+ aggiunge Tendenze, forma recente e confronti testa a testa.",
    hook="Scopri chi comanda oltre il tabellino.",
    intro="StatScout confronta ogni giocatore NBA con il proprio gruppo di ruolo usando i numeri degli analisti: true shooting, usage, zone di tiro, regia, rimbalzi, difesa e impatto in campo. Ogni metrica è una barra di percentile, così l'élite e chi fatica saltano all'occhio.",
    free="GRATIS",
    free_items=["Risultati live, tabellini e classifiche", "Classifiche per percentile per guardie, ali e centri", "Profili completi con statistiche avanzate e classiche", "Segui la tua squadra e i tuoi giocatori preferiti"],
    plus_items=["Tendenze: tutta la lega ordinata per chi è in crescita o in calo", "Forma recente nell'ultima settimana, 2 o 4 settimane", "Confronti tra giocatori e andamento anno per anno", "Valutazioni dei giocatori in ogni tabellino", "Ogni stagione dal 2002-03"],
    privacy_line="Nessun account, nessuna pubblicità, nessun tracciamento.",
    terms="StatScout+ è disponibile mensile o annuale (entrambi con 7 giorni di prova gratuita) o come acquisto unico a vita. Il pagamento è addebitato sul tuo ID Apple. L'abbonamento si rinnova automaticamente se non viene disdetto almeno 24 ore prima della fine del periodo; gestiscilo nelle impostazioni del tuo ID Apple.",
    privacy_label="Privacy", terms_label="Termini d'uso (EULA)",
    disclaimer="Non affiliato né approvato dalla NBA o dalle sue squadre.",
)

L["pt-BR"] = dict(
    name="Basquete: " + BRAND,
    subtitle="Estatísticas avançadas da NBA",
    keywords="basketball,percentil,jogadores,comparar,ranking,placar,ao vivo,box score,times,classificação",
    promo="Grátis: placares ao vivo, box scores, classificação e percentis de cada jogador da NBA. O StatScout+ traz Tendências, fase recente e duelos frente a frente.",
    hook="Veja quem lidera além do box score.",
    intro="O StatScout compara cada jogador da NBA com o próprio grupo de posição usando os números dos analistas: true shooting, uso, zonas de arremesso, criação, rebotes, defesa e impacto em quadra. Cada métrica é uma barra de percentil, então a elite e quem está mal aparecem na hora.",
    free="GRÁTIS",
    free_items=["Placares ao vivo, box scores e classificação", "Rankings por percentil para armadores, alas e pivôs", "Perfis completos com estatísticas avançadas e tradicionais", "Siga seu time e seus jogadores favoritos"],
    plus_items=["Tendências: a liga inteira ordenada por quem está em alta ou em baixa", "Fase recente na última semana, 2 ou 4 semanas", "Duelos entre jogadores e evolução ano a ano", "Notas dos jogadores em cada box score", "Todas as temporadas desde 2002-03"],
    privacy_line="Sem conta, sem anúncios, sem rastreamento.",
    terms="O StatScout+ é oferecido mensal ou anual (ambos com 7 dias grátis) ou como compra vitalícia única. O pagamento é cobrado no seu ID Apple. As assinaturas renovam automaticamente, a menos que sejam canceladas pelo menos 24 horas antes do fim do período; gerencie nos ajustes do seu ID Apple.",
    privacy_label="Privacidade", terms_label="Termos de uso (EULA)",
    disclaimer="Sem afiliação ou endosso da NBA ou de seus times.",
)
L["pt-PT"] = dict(L["pt-BR"],
    keywords="basquetebol,percentil,jogadores,comparar,ranking,resultados,direto,box score,equipas",
    promo="Grátis: resultados em direto, box scores, classificações e percentis de cada jogador da NBA. O StatScout+ junta Tendências, forma recente e duelos frente a frente.",
    intro="O StatScout compara cada jogador da NBA com o seu grupo de posição usando os números dos analistas: true shooting, utilização, zonas de lançamento, criação, ressaltos, defesa e impacto em campo. Cada métrica é uma barra de percentil, por isso a elite e quem está em dificuldades destacam-se logo.",
    free_items=["Resultados em direto, box scores e classificações", "Rankings por percentil para bases, extremos e postes", "Perfis completos com estatísticas avançadas e clássicas", "Siga a sua equipa e os seus jogadores favoritos"],
    plus_items=["Tendências: toda a liga ordenada por quem está em alta ou em baixa", "Forma recente na última semana, 2 ou 4 semanas", "Duelos entre jogadores e evolução ano a ano", "Avaliação dos jogadores em cada box score", "Todas as épocas desde 2002-03"],
    privacy_line="Sem conta, sem anúncios, sem rastreio.",
    terms="O StatScout+ é oferecido mensal ou anual (ambos com 7 dias grátis) ou como compra vitalícia única. O pagamento é cobrado no seu ID Apple. As subscrições renovam automaticamente, salvo cancelamento pelo menos 24 horas antes do fim do período; faça a gestão nas definições do seu ID Apple.",
    disclaimer="Sem afiliação nem aprovação da NBA ou das suas equipas.",
)

L["nl-NL"] = dict(
    name="Basketbal: " + BRAND,
    subtitle="Geavanceerde NBA-statistieken",
    keywords="basketball,percentiel,spelers,vergelijken,ranglijst,uitslagen,live,boxscore,teams,stand",
    promo="Gratis: live uitslagen, boxscores, standen en percentielranglijsten voor elke NBA-speler. StatScout+ voegt Trends, recente vorm en onderlinge vergelijkingen toe.",
    hook="Zie wie er echt de dienst uitmaakt, voorbij de boxscore.",
    intro="StatScout meet elke NBA-speler aan zijn eigen positiegroep met de cijfers die analisten gebruiken: true shooting, usage, schotzones, spelopbouw, rebounds, verdediging en impact op het veld. Elke statistiek is een percentielbalk, dus de top en de achterblijvers zie je meteen.",
    free="GRATIS",
    free_items=["Live uitslagen, boxscores en standen", "Percentielranglijsten voor guards, forwards en centers", "Volledige spelersprofielen met geavanceerde en klassieke cijfers", "Volg je team en favoriete spelers"],
    plus_items=["Trends: de hele competitie gerangschikt op wie stijgt of daalt", "Recente vorm over de laatste week, 2 of 4 weken", "Spelers vergelijken en ontwikkeling per seizoen", "Spelersbeoordelingen in elke boxscore", "Elk seizoen terug tot 2002-03"],
    privacy_line="Geen account, geen advertenties, geen tracking.",
    terms="StatScout+ is er per maand of per jaar (beide met 7 dagen gratis) of als eenmalige levenslange aankoop. De betaling wordt via je Apple ID afgeschreven. Abonnementen verlengen automatisch tenzij ze minstens 24 uur voor het einde van de periode worden opgezegd; beheer ze in de instellingen van je Apple ID.",
    privacy_label="Privacy", terms_label="Gebruiksvoorwaarden (EULA)",
    disclaimer="Niet gelieerd aan of goedgekeurd door de NBA of haar teams.",
)

L["sv"] = dict(
    name="Basketboll: " + BRAND,
    subtitle="Avancerad NBA-statistik",
    keywords="basket,percentil,spelare,jämför,ranking,resultat,live,boxscore,lag,tabell",
    promo="Gratis: liveresultat, boxscores, tabeller och percentilrankning för varje NBA-spelare. StatScout+ ger Trender, aktuell form och spelarjämförelser.",
    hook="Se vem som leder bortom boxscoren.",
    intro="StatScout jämför varje NBA-spelare med hans egen positionsgrupp med siffrorna analytiker använder: true shooting, usage, skottzoner, speluppbyggnad, returer, försvar och påverkan på planen. Varje mått är en percentilstapel, så eliten och de som kämpar syns direkt.",
    free="GRATIS",
    free_items=["Liveresultat, boxscores och tabeller", "Percentilrankning för guards, forwards och centrar", "Fullständiga spelarprofiler med avancerad och vanlig statistik", "Följ ditt lag och dina favoritspelare"],
    plus_items=["Trender: hela ligan rankad efter vem som är het eller kall", "Aktuell form senaste veckan, 2 eller 4 veckorna", "Spelarjämförelser och utveckling år för år", "Spelarbetyg i varje boxscore", "Varje säsong tillbaka till 2002-03"],
    privacy_line="Inget konto, ingen reklam, ingen spårning.",
    terms="StatScout+ finns per månad eller år (båda med 7 dagars gratis provperiod) eller som ett engångsköp för livstid. Betalningen dras från ditt Apple-ID. Prenumerationer förnyas automatiskt om de inte sägs upp minst 24 timmar före periodens slut; hantera dem i inställningarna för ditt Apple-ID.",
    privacy_label="Integritet", terms_label="Användarvillkor (EULA)",
    disclaimer="Inte ansluten till eller godkänd av NBA eller dess lag.",
)

L["da"] = dict(
    name="Basketball: " + BRAND,
    subtitle="Avanceret NBA-statistik",
    keywords="basket,percentil,spillere,sammenlign,rangliste,resultater,live,boxscore,hold,stilling",
    promo="Gratis: liveresultater, boxscores, stillinger og percentilranglister for hver NBA-spiller. StatScout+ giver Trends, aktuel form og spillersammenligninger.",
    hook="Se hvem der fører, ud over boxscoren.",
    intro="StatScout måler hver NBA-spiller mod hans egen positionsgruppe med de tal, analytikere bruger: true shooting, usage, skudzoner, spilopbygning, rebounds, forsvar og indflydelse på banen. Hver måling er en percentilbjælke, så eliten og dem der kæmper ses med det samme.",
    free="GRATIS",
    free_items=["Liveresultater, boxscores og stillinger", "Percentilranglister for guards, forwards og centre", "Fulde spillerprofiler med avancerede og klassiske tal", "Følg dit hold og dine yndlingsspillere"],
    plus_items=["Trends: hele ligaen rangeret efter hvem der er varm eller kold", "Aktuel form over den seneste uge, 2 eller 4 uger", "Spillersammenligninger og udvikling år for år", "Spillerkarakterer i hver boxscore", "Alle sæsoner tilbage til 2002-03"],
    privacy_line="Ingen konto, ingen reklamer, ingen sporing.",
    terms="StatScout+ fås månedligt eller årligt (begge med 7 dages gratis prøve) eller som et engangskøb for livstid. Betalingen trækkes på dit Apple-id. Abonnementer fornyes automatisk, medmindre de opsiges mindst 24 timer før periodens udløb; administrer dem i indstillingerne for dit Apple-id.",
    privacy_label="Privatliv", terms_label="Vilkår (EULA)",
    disclaimer="Ikke tilknyttet eller godkendt af NBA eller dets hold.",
)

L["no"] = dict(
    name="Basketball: " + BRAND,
    subtitle="Avansert NBA-statistikk",
    keywords="basket,persentil,spillere,sammenlign,rangering,resultater,live,boxscore,lag,tabell",
    promo="Gratis: liveresultater, boxscores, tabeller og persentilrangering for hver NBA-spiller. StatScout+ gir Trender, aktuell form og spillersammenligninger.",
    hook="Se hvem som leder, utover boxscoren.",
    intro="StatScout måler hver NBA-spiller mot hans egen posisjonsgruppe med tallene analytikere bruker: true shooting, usage, skuddsoner, spilloppbygging, returer, forsvar og innvirkning på banen. Hver måling er en persentilsøyle, så eliten og de som sliter vises med en gang.",
    free="GRATIS",
    free_items=["Liveresultater, boxscores og tabeller", "Persentilrangering for guards, forwards og sentere", "Fullstendige spillerprofiler med avansert og vanlig statistikk", "Følg laget ditt og favorittspillerne dine"],
    plus_items=["Trender: hele ligaen rangert etter hvem som er varm eller kald", "Aktuell form siste uke, 2 eller 4 uker", "Spillersammenligninger og utvikling år for år", "Spillerkarakterer i hver boxscore", "Hver sesong tilbake til 2002-03"],
    privacy_line="Ingen konto, ingen reklame, ingen sporing.",
    terms="StatScout+ tilbys månedlig eller årlig (begge med 7 dagers gratis prøve) eller som et engangskjøp for livstid. Betalingen belastes Apple-ID-en din. Abonnementer fornyes automatisk med mindre de sies opp minst 24 timer før periodens slutt; administrer dem i innstillingene for Apple-ID-en.",
    privacy_label="Personvern", terms_label="Vilkår (EULA)",
    disclaimer="Ikke tilknyttet eller godkjent av NBA eller lagene.",
)

L["fi"] = dict(
    name="Koripallo: " + BRAND,
    subtitle="Edistyneet NBA-tilastot",
    keywords="basketball,persentiili,pelaajat,vertailu,tulokset,live,boxscore,joukkueet,sarjataulukko",
    promo="Ilmainen: livetulokset, boxscoret, sarjataulukot ja persentiilit jokaiselle NBA-pelaajalle. StatScout+ tuo Trendit, tuoreen vireen ja pelaajavertailut.",
    hook="Näe, kuka johtaa boxscoren takana.",
    intro="StatScout vertaa jokaista NBA-pelaajaa hänen omaan pelipaikkaryhmäänsä analyytikoiden luvuilla: true shooting, usage, heittoalueet, pelinrakennus, levypallot, puolustus ja vaikutus kentällä. Jokainen mittari on persentiilipalkki, joten huiput ja vaikeuksissa olevat erottuvat heti.",
    free="ILMAISEKSI",
    free_items=["Livetulokset, boxscoret ja sarjataulukot", "Persentiilirankingit takamiehille, laitureille ja senttereille", "Täydet pelaajaprofiilit edistyneillä ja perinteisillä tilastoilla", "Seuraa joukkuettasi ja suosikkipelaajiasi"],
    plus_items=["Trendit: koko liiga järjestettynä sen mukaan, kuka on kuumana tai kylmänä", "Tuore vire viimeiseltä viikolta, 2 tai 4 viikolta", "Pelaajavertailut ja kehitys vuodesta toiseen", "Pelaajien arvosanat jokaisessa boxscoressa", "Jokainen kausi vuoteen 2002-03 asti"],
    privacy_line="Ei tiliä, ei mainoksia, ei seurantaa.",
    terms="StatScout+ on saatavilla kuukausittain tai vuosittain (molemmissa 7 päivän ilmainen kokeilu) tai kertaostona elinajaksi. Maksu veloitetaan Apple ID:ltäsi. Tilaukset uusiutuvat automaattisesti, ellei niitä peruta vähintään 24 tuntia ennen jakson loppua; hallitse niitä Apple ID:n asetuksissa.",
    privacy_label="Tietosuoja", terms_label="Käyttöehdot (EULA)",
    disclaimer="Ei NBA:n tai sen joukkueiden kanssa yhteydessä eikä niiden hyväksymä.",
)

L["pl"] = dict(
    name="Koszykówka: " + BRAND,
    subtitle="Zaawansowane statystyki NBA",
    keywords="basketball,kosz,percentyl,zawodnicy,porównanie,ranking,wyniki,na żywo,box score,tabela",
    promo="Za darmo: wyniki na żywo, box score, tabele i percentyle każdego zawodnika NBA. StatScout+ dodaje Trendy, aktualną formę i porównania zawodników.",
    hook="Zobacz, kto naprawdę prowadzi poza box score.",
    intro="StatScout porównuje każdego zawodnika NBA z jego własną grupą pozycji, używając liczb analityków: true shooting, usage, strefy rzutowe, rozegranie, zbiórki, obrona i wpływ na boisko. Każda statystyka to pasek percentyla, więc elita i słabsi są widoczni od razu.",
    free="ZA DARMO",
    free_items=["Wyniki na żywo, box score i tabele", "Rankingi percentylowe dla obrońców, skrzydłowych i środkowych", "Pełne profile zawodników ze statystykami zaawansowanymi i klasycznymi", "Obserwuj swoją drużynę i ulubionych zawodników"],
    plus_items=["Trendy: cała liga według tego, kto jest w formie, a kto obniża loty", "Aktualna forma z ostatniego tygodnia, 2 lub 4 tygodni", "Porównania zawodników i postępy rok do roku", "Oceny zawodników w każdym box score", "Każdy sezon od 2002-03"],
    privacy_line="Bez konta, bez reklam, bez śledzenia.",
    terms="StatScout+ jest dostępny miesięcznie lub rocznie (oba z 7-dniowym darmowym okresem próbnym) albo jako jednorazowy zakup dożywotni. Płatność pobierana jest z konta Apple ID. Subskrypcja odnawia się automatycznie, jeśli nie zostanie anulowana co najmniej 24 godziny przed końcem okresu; zarządzaj nią w ustawieniach Apple ID.",
    privacy_label="Prywatność", terms_label="Warunki korzystania (EULA)",
    disclaimer="Brak powiązań z NBA ani jej drużynami i brak ich poparcia.",
)

L["cs"] = dict(
    name="Basketbal: " + BRAND,
    subtitle="Pokročilé statistiky NBA",
    keywords="basketball,košíková,percentil,hráči,porovnání,žebříček,výsledky,živě,box score,tabulka",
    promo="Zdarma: živé výsledky, box score, tabulky a percentily každého hráče NBA. StatScout+ přidává Trendy, aktuální formu a srovnání hráčů.",
    hook="Zjistěte, kdo vede i mimo box score.",
    intro="StatScout porovnává každého hráče NBA s jeho vlastní skupinou postů pomocí čísel, která používají analytici: true shooting, usage, střelecké zóny, rozehrávka, doskoky, obrana a vliv na hřišti. Každá metrika je percentilový pruh, takže elita i ti, kdo se trápí, jsou vidět hned.",
    free="ZDARMA",
    free_items=["Živé výsledky, box score a tabulky", "Percentilové žebříčky pro rozehrávače, křídla a pivoty", "Úplné profily hráčů s pokročilými i klasickými statistikami", "Sledujte svůj tým a oblíbené hráče"],
    plus_items=["Trendy: celá liga seřazená podle toho, kdo je ve formě a kdo ne", "Aktuální forma za poslední týden, 2 nebo 4 týdny", "Srovnání hráčů a vývoj rok po roce", "Hodnocení hráčů v každém box score", "Každá sezóna zpět do 2002-03"],
    privacy_line="Bez účtu, bez reklam, bez sledování.",
    terms="StatScout+ je k dispozici měsíčně nebo ročně (obojí se 7denní zkušební dobou zdarma) nebo jako jednorázový doživotní nákup. Platba se strhne z vašeho Apple ID. Předplatné se automaticky obnovuje, pokud ho nezrušíte alespoň 24 hodin před koncem období; spravujte ho v nastavení Apple ID.",
    privacy_label="Soukromí", terms_label="Podmínky použití (EULA)",
    disclaimer="Bez vazby na NBA nebo její týmy a bez jejich schválení.",
)

L["sk"] = dict(
    name="Basketbal: " + BRAND,
    subtitle="Pokročilé štatistiky NBA",
    keywords="basketball,percentil,hráči,porovnanie,rebríček,výsledky,naživo,box score,tabuľka,tímy",
    promo="Zadarmo: výsledky naživo, box score, tabuľky a percentily každého hráča NBA. StatScout+ pridáva Trendy, aktuálnu formu a porovnania hráčov.",
    hook="Zistite, kto vedie aj mimo box score.",
    intro="StatScout porovnáva každého hráča NBA s jeho vlastnou skupinou postov pomocou čísel analytikov: true shooting, usage, strelecké zóny, rozohrávka, doskoky, obrana a vplyv na ihrisku. Každá metrika je percentilový pruh, takže elita aj tí, čo sa trápia, sú viditeľní hneď.",
    free="ZADARMO",
    free_items=["Výsledky naživo, box score a tabuľky", "Percentilové rebríčky pre rozohrávačov, krídla a pivotov", "Úplné profily hráčov s pokročilými aj klasickými štatistikami", "Sledujte svoj tím a obľúbených hráčov"],
    plus_items=["Trendy: celá liga zoradená podľa toho, kto je vo forme a kto nie", "Aktuálna forma za posledný týždeň, 2 alebo 4 týždne", "Porovnania hráčov a vývoj rok po roku", "Hodnotenia hráčov v každom box score", "Každá sezóna späť do 2002-03"],
    privacy_line="Bez účtu, bez reklám, bez sledovania.",
    terms="StatScout+ je dostupný mesačne alebo ročne (oboje so 7-dňovou skúšobnou dobou zadarmo) alebo ako jednorazový doživotný nákup. Platba sa strhne z vášho Apple ID. Predplatné sa automaticky obnovuje, ak ho nezrušíte aspoň 24 hodín pred koncom obdobia; spravujte ho v nastaveniach Apple ID.",
    privacy_label="Súkromie", terms_label="Podmienky používania (EULA)",
    disclaimer="Bez prepojenia s NBA alebo jej tímami a bez ich schválenia.",
)

L["hr"] = dict(
    name="Košarka: " + BRAND,
    subtitle="Napredna NBA statistika",
    keywords="basketball,percentil,igrači,usporedba,poredak,rezultati,uživo,box score,timovi,tablica",
    promo="Besplatno: rezultati uživo, box score, tablice i percentili za svakog NBA igrača. StatScout+ donosi Trendove, trenutnu formu i usporedbe igrača.",
    hook="Pogledajte tko vodi i izvan box scorea.",
    intro="StatScout uspoređuje svakog NBA igrača s njegovom vlastitom skupinom pozicija brojkama koje koriste analitičari: true shooting, usage, zone šuta, organizacija igre, skokovi, obrana i utjecaj na terenu. Svaka metrika je percentilna traka pa se elita i oni koji se muče vide odmah.",
    free="BESPLATNO",
    free_items=["Rezultati uživo, box score i tablice", "Percentilni poreci za bekove, krila i centre", "Potpuni profili igrača s naprednom i klasičnom statistikom", "Pratite svoj tim i omiljene igrače"],
    plus_items=["Trendovi: cijela liga poredana po tome tko je u usponu, a tko u padu", "Trenutna forma u zadnjem tjednu, 2 ili 4 tjedna", "Usporedbe igrača i napredak iz godine u godinu", "Ocjene igrača u svakom box scoreu", "Svaka sezona unatrag do 2002-03"],
    privacy_line="Bez računa, bez oglasa, bez praćenja.",
    terms="StatScout+ je dostupan mjesečno ili godišnje (oboje uz 7 dana besplatne probe) ili kao jednokratna doživotna kupnja. Plaćanje se naplaćuje s vašeg Apple ID-a. Pretplate se automatski obnavljaju ako se ne otkažu najmanje 24 sata prije kraja razdoblja; upravljajte njima u postavkama Apple ID-a.",
    privacy_label="Privatnost", terms_label="Uvjeti korištenja (EULA)",
    disclaimer="Nije povezano s NBA-om ni njegovim timovima niti ga oni podržavaju.",
)

L["hu"] = dict(
    name="Kosárlabda: " + BRAND,
    subtitle="Haladó NBA-statisztikák",
    keywords="basketball,kosár,percentilis,játékosok,összehasonlítás,rangsor,eredmények,élő,box score",
    promo="Ingyenes: élő eredmények, box score-ok, tabellák és percentilis rangsorok minden NBA-játékosra. A StatScout+ hozza a Trendeket, a friss formát és a játékos-összevetést.",
    hook="Nézd meg, ki vezet a box score-on túl.",
    intro="A StatScout minden NBA-játékost a saját posztcsoportjához méri az elemzők számaival: true shooting, usage, dobózónák, irányítás, lepattanók, védekezés és pályára gyakorolt hatás. Minden mutató egy percentilis sáv, így az elit és a küszködők azonnal látszanak.",
    free="INGYENES",
    free_items=["Élő eredmények, box score-ok és tabellák", "Percentilis rangsorok hátvédeknek, bedobóknak és centereknek", "Teljes játékosprofilok haladó és hagyományos statisztikákkal", "Kövesd a csapatodat és a kedvenc játékosaidat"],
    plus_items=["Trendek: az egész liga aszerint, ki van formában és ki hanyatlik", "Friss forma az elmúlt héten, 2 vagy 4 héten", "Játékos-összevetések és fejlődés évről évre", "Játékosértékelések minden box score-ban", "Minden szezon 2002-03-ig visszamenőleg"],
    privacy_line="Nincs fiók, nincs reklám, nincs követés.",
    terms="A StatScout+ havi vagy éves előfizetéssel (mindkettő 7 napos ingyenes próbával) vagy egyszeri, örökös vásárlással érhető el. A fizetés az Apple ID-dat terheli. Az előfizetés automatikusan megújul, hacsak nem mondod le legalább 24 órával az időszak vége előtt; kezeld az Apple ID beállításaiban.",
    privacy_label="Adatvédelem", terms_label="Felhasználási feltételek (EULA)",
    disclaimer="Nem kapcsolódik az NBA-hez vagy csapataihoz, és nem ők támogatják.",
)

L["ro"] = dict(
    name="Baschet: " + BRAND,
    subtitle="Statistici NBA avansate",
    keywords="basketball,percentilă,jucători,comparație,clasament,rezultate,live,box score,echipe",
    promo="Gratuit: scoruri live, box score, clasamente și percentile pentru fiecare jucător NBA. StatScout+ adaugă Tendințe, forma recentă și comparații între jucători.",
    hook="Vezi cine conduce dincolo de box score.",
    intro="StatScout compară fiecare jucător NBA cu propriul grup de posturi folosind cifrele analiștilor: true shooting, usage, zone de aruncare, construcție, recuperări, apărare și impact pe teren. Fiecare indicator este o bară de percentilă, așa că elita și cei în dificultate se văd imediat.",
    free="GRATUIT",
    free_items=["Scoruri live, box score și clasamente", "Clasamente pe percentile pentru fundași, extreme și pivoți", "Profiluri complete cu statistici avansate și clasice", "Urmărește-ți echipa și jucătorii preferați"],
    plus_items=["Tendințe: toată liga ordonată după cine e în formă și cine scade", "Forma recentă din ultima săptămână, 2 sau 4 săptămâni", "Comparații între jucători și evoluția an de an", "Note pentru jucători în fiecare box score", "Fiecare sezon până în 2002-03"],
    privacy_line="Fără cont, fără reclame, fără urmărire.",
    terms="StatScout+ este disponibil lunar sau anual (ambele cu 7 zile de probă gratuită) sau ca achiziție unică pe viață. Plata se face prin ID-ul tău Apple. Abonamentele se reînnoiesc automat dacă nu sunt anulate cu cel puțin 24 de ore înainte de sfârșitul perioadei; gestionează-le în setările ID-ului Apple.",
    privacy_label="Confidențialitate", terms_label="Termeni de utilizare (EULA)",
    disclaimer="Nu este afiliat sau aprobat de NBA sau de echipele sale.",
)

L["el"] = dict(
    name="Μπάσκετ: " + BRAND,
    subtitle="Προηγμένα στατιστικά NBA",
    keywords="basketball,εκατοστημόριο,παίκτες,σύγκριση,κατάταξη,σκορ,live,box score,ομάδες,βαθμολογία",
    promo="Δωρεάν: ζωντανά σκορ, box score, βαθμολογίες και εκατοστημόρια για κάθε παίκτη του NBA. Το StatScout+ προσθέτει Τάσεις, πρόσφατη φόρμα και συγκρίσεις παικτών.",
    hook="Δες ποιος ξεχωρίζει πέρα από το box score.",
    intro="Το StatScout συγκρίνει κάθε παίκτη του NBA με τη δική του ομάδα θέσεων, με τους αριθμούς των αναλυτών: true shooting, usage, ζώνες σουτ, δημιουργία, ριμπάουντ, άμυνα και επίδραση στο παρκέ. Κάθε δείκτης είναι μια μπάρα εκατοστημορίου, οπότε η ελίτ και όσοι δυσκολεύονται φαίνονται αμέσως.",
    free="ΔΩΡΕΑΝ",
    free_items=["Ζωντανά σκορ, box score και βαθμολογίες", "Κατατάξεις εκατοστημορίων για γκαρντ, φόργουορντ και σέντερ", "Πλήρη προφίλ παικτών με προηγμένα και κλασικά στατιστικά", "Ακολούθησε την ομάδα σου και τους αγαπημένους σου παίκτες"],
    plus_items=["Τάσεις: όλη η λίγκα με βάση ποιος ανεβαίνει ή πέφτει", "Πρόσφατη φόρμα της τελευταίας εβδομάδας, 2 ή 4 εβδομάδων", "Συγκρίσεις παικτών και εξέλιξη ανά χρονιά", "Βαθμολογίες παικτών σε κάθε box score", "Κάθε σεζόν έως το 2002-03"],
    privacy_line="Χωρίς λογαριασμό, χωρίς διαφημίσεις, χωρίς παρακολούθηση.",
    terms="Το StatScout+ διατίθεται μηνιαία ή ετήσια (και τα δύο με 7 ημέρες δωρεάν δοκιμή) ή ως εφάπαξ αγορά εφ' όρου ζωής. Η χρέωση γίνεται στο Apple ID σου. Οι συνδρομές ανανεώνονται αυτόματα εκτός αν ακυρωθούν τουλάχιστον 24 ώρες πριν από το τέλος της περιόδου· διαχειρίσου τες στις ρυθμίσεις του Apple ID.",
    privacy_label="Απόρρητο", terms_label="Όροι χρήσης (EULA)",
    disclaimer="Δεν συνδέεται ούτε εγκρίνεται από το NBA ή τις ομάδες του.",
)

L["tr"] = dict(
    name="Basketbol: " + BRAND,
    subtitle="Gelişmiş NBA istatistikleri",
    keywords="basketball,yüzdelik,oyuncu,karşılaştır,sıralama,skor,canlı,box score,takım,puan durumu",
    promo="Ücretsiz: canlı skorlar, box score'lar, puan durumu ve her NBA oyuncusu için yüzdelik sıralamalar. StatScout+ Trendler, güncel form ve oyuncu karşılaştırmaları ekler.",
    hook="Box score'un ötesinde kimin öne çıktığını gör.",
    intro="StatScout her NBA oyuncusunu kendi pozisyon grubuyla, analistlerin kullandığı sayılarla karşılaştırır: true shooting, kullanım oranı, şut bölgeleri, oyun kurma, ribaund, savunma ve sahadaki etki. Her metrik bir yüzdelik çubuğudur; elit oyuncular ve zorlananlar bir bakışta görünür.",
    free="ÜCRETSİZ",
    free_items=["Canlı skorlar, box score'lar ve puan durumu", "Gard, forvet ve pivotlar için yüzdelik sıralamalar", "Gelişmiş ve klasik istatistiklerle tam oyuncu profilleri", "Takımını ve favori oyuncularını takip et"],
    plus_items=["Trendler: tüm lig kimin yükselişte, kimin düşüşte olduğuna göre", "Son 1, 2 veya 4 haftalık güncel form", "Oyuncu karşılaştırmaları ve yıldan yıla gelişim", "Her box score'da oyuncu notları", "2002-03'e kadar her sezon"],
    privacy_line="Hesap yok, reklam yok, takip yok.",
    terms="StatScout+ aylık veya yıllık (ikisi de 7 gün ücretsiz deneme ile) ya da tek seferlik ömür boyu satın alma olarak sunulur. Ödeme Apple Kimliğinizden alınır. Abonelikler, dönem bitmeden en az 24 saat önce iptal edilmezse otomatik yenilenir; Apple Kimliği ayarlarından yönetebilirsiniz.",
    privacy_label="Gizlilik", terms_label="Kullanım Koşulları (EULA)",
    disclaimer="NBA veya takımlarıyla bağlantılı değildir ve onlar tarafından onaylanmamıştır.",
)

L["ru"] = dict(
    name="Баскетбол: " + BRAND,
    subtitle="Продвинутая статистика NBA",
    keywords="basketball,перцентиль,игроки,сравнение,рейтинг,счет,онлайн,box score,команды,таблица",
    promo="Бесплатно: счет в реальном времени, протоколы матчей, таблицы и перцентили каждого игрока NBA. StatScout+ добавляет Тренды, текущую форму и сравнение игроков.",
    hook="Узнайте, кто лидирует за пределами протокола.",
    intro="StatScout сравнивает каждого игрока NBA с его собственной группой позиций по цифрам аналитиков: true shooting, usage, зоны бросков, организация атак, подборы, защита и влияние на площадке. Каждый показатель — полоса перцентиля, поэтому элита и те, кому тяжело, видны сразу.",
    free="БЕСПЛАТНО",
    free_items=["Счет в реальном времени, протоколы и таблицы", "Перцентильные рейтинги защитников, форвардов и центровых", "Полные профили игроков с продвинутой и классической статистикой", "Следите за своей командой и любимыми игроками"],
    plus_items=["Тренды: вся лига по тому, кто на подъеме, а кто сдает", "Текущая форма за последнюю неделю, 2 или 4 недели", "Сравнение игроков и динамика по сезонам", "Оценки игроков в каждом протоколе", "Все сезоны вплоть до 2002-03"],
    privacy_line="Без аккаунта, без рекламы, без отслеживания.",
    terms="StatScout+ доступен помесячно или на год (оба варианта с 7-дневным бесплатным периодом) или как разовая покупка навсегда. Оплата списывается с вашего Apple ID. Подписка продлевается автоматически, если ее не отменить как минимум за 24 часа до конца периода; управляйте ею в настройках Apple ID.",
    privacy_label="Конфиденциальность", terms_label="Условия использования (EULA)",
    disclaimer="Не связано с NBA или ее командами и не одобрено ими.",
)

L["uk"] = dict(
    name="Баскетбол: " + BRAND,
    subtitle="Розширена статистика NBA",
    keywords="basketball,перцентиль,гравці,порівняння,рейтинг,рахунок,наживо,box score,команди,таблиця",
    promo="Безкоштовно: рахунок наживо, протоколи матчів, таблиці та перцентилі кожного гравця NBA. StatScout+ додає Тренди, поточну форму та порівняння гравців.",
    hook="Дізнайтеся, хто лідирує поза протоколом.",
    intro="StatScout порівнює кожного гравця NBA з його власною групою позицій за цифрами аналітиків: true shooting, usage, зони кидків, організація атак, підбирання, захист і вплив на майданчику. Кожен показник — смуга перцентиля, тож еліту й тих, кому важко, видно одразу.",
    free="БЕЗКОШТОВНО",
    free_items=["Рахунок наживо, протоколи й таблиці", "Перцентильні рейтинги захисників, форвардів і центрових", "Повні профілі гравців із розширеною та класичною статистикою", "Стежте за своєю командою й улюбленими гравцями"],
    plus_items=["Тренди: уся ліга за тим, хто на підйомі, а хто здає", "Поточна форма за останній тиждень, 2 або 4 тижні", "Порівняння гравців і динаміка за сезонами", "Оцінки гравців у кожному протоколі", "Усі сезони аж до 2002-03"],
    privacy_line="Без акаунта, без реклами, без стеження.",
    terms="StatScout+ доступний щомісяця або на рік (обидва з 7-денним безкоштовним періодом) чи як разова довічна покупка. Оплата списується з вашого Apple ID. Підписка поновлюється автоматично, якщо її не скасувати щонайменше за 24 години до кінця періоду; керуйте нею в налаштуваннях Apple ID.",
    privacy_label="Конфіденційність", terms_label="Умови використання (EULA)",
    disclaimer="Не пов'язано з NBA чи її командами й не схвалено ними.",
)

L["ja"] = dict(
    name="バスケ: " + BRAND,
    subtitle="NBAの詳細スタッツと分析",
    keywords="バスケットボール,パーセンタイル,選手,比較,ランキング,速報,スコア,ボックススコア,順位表,チーム",
    promo="無料：ライブスコア、ボックススコア、順位表、全NBA選手のパーセンタイル順位。StatScout+ならトレンド、直近の調子、選手比較も。",
    hook="ボックススコアの先にいる本当のリーダーを見つけよう。",
    intro="StatScoutはNBAの全選手を同じポジション群の中で、アナリストが使う数字でランク付けします。TS%、USG%、シュートゾーン、プレーメイク、リバウンド、ディフェンス、コート上の影響力。すべての指標がパーセンタイルバーで表示されるので、トップ選手も苦しんでいる選手もひと目で分かります。",
    free="無料",
    free_items=["ライブスコア、ボックススコア、順位表", "ガード・フォワード・センター別のパーセンタイル順位", "詳細スタッツと基本スタッツを備えた選手プロフィール", "応援するチームや好きな選手をフォロー"],
    plus_items=["トレンド：好調・不調でリーグ全体をランク付け", "直近1週間・2週間・4週間の調子", "選手同士の比較とシーズンごとの推移", "全試合のボックススコアに選手評価", "2002-03シーズン以降の全シーズン"],
    privacy_line="アカウント不要、広告なし、トラッキングなし。",
    terms="StatScout+は月額または年額（どちらも7日間の無料トライアル付き）、または買い切りの永久版で利用できます。お支払いはApple IDに請求されます。サブスクリプションは期間終了の24時間前までに解約しない限り自動更新されます。Apple IDの設定から管理できます。",
    privacy_label="プライバシー", terms_label="利用規約（EULA）",
    disclaimer="NBAおよび所属チームとは提携・承認関係にありません。",
)

L["ko"] = dict(
    name="농구: " + BRAND,
    subtitle="NBA 고급 기록과 분석",
    keywords="basketball,백분위,선수,비교,랭킹,라이브,스코어,박스스코어,순위,팀",
    promo="무료: 라이브 스코어, 박스스코어, 순위표, 모든 NBA 선수의 백분위 순위. StatScout+는 트렌드, 최근 폼, 선수 맞대결 비교를 더합니다.",
    hook="박스스코어 너머의 진짜 리더를 확인하세요.",
    intro="StatScout는 모든 NBA 선수를 같은 포지션 그룹 안에서 분석가들이 쓰는 숫자로 순위를 매깁니다. 트루 슈팅, 사용률, 슛 구역, 플레이메이킹, 리바운드, 수비, 코트 위 영향력까지. 모든 지표가 백분위 막대로 표시되어 정상급 선수와 고전하는 선수가 한눈에 보입니다.",
    free="무료",
    free_items=["라이브 스코어, 박스스코어, 순위표", "가드, 포워드, 센터별 백분위 순위", "고급 기록과 기본 기록을 담은 선수 프로필", "응원하는 팀과 좋아하는 선수 팔로우"],
    plus_items=["트렌드: 상승세와 하락세로 정리한 리그 전체", "최근 1주, 2주, 4주 폼", "선수 맞대결 비교와 시즌별 변화", "모든 박스스코어의 선수 평점", "2002-03 시즌부터 모든 시즌"],
    privacy_line="계정 없음, 광고 없음, 추적 없음.",
    terms="StatScout+는 월간 또는 연간(모두 7일 무료 체험 포함) 구독이나 1회 평생 구매로 이용할 수 있습니다. 결제는 Apple ID로 청구됩니다. 구독은 기간 종료 최소 24시간 전에 취소하지 않으면 자동 갱신되며, Apple ID 설정에서 관리할 수 있습니다.",
    privacy_label="개인정보 처리방침", terms_label="이용 약관(EULA)",
    disclaimer="NBA 및 소속 팀과 제휴하거나 승인받지 않았습니다.",
)

L["zh-Hans"] = dict(
    name="篮球: " + BRAND,
    subtitle="NBA进阶数据与分析",
    keywords="basketball,百分位,球员,对比,排名,比分,直播,技术统计,球队,积分榜",
    promo="免费：实时比分、技术统计、积分榜，以及每位NBA球员的百分位排名。StatScout+ 再添趋势榜、近期状态和球员对比。",
    hook="看清技术统计之外真正的领跑者。",
    intro="StatScout 用分析师使用的数据，将每位NBA球员与同位置组的球员比较：真实命中率、使用率、投篮区域、组织、篮板、防守和场上影响力。每项数据都是一条百分位条，顶尖与挣扎的球员一眼可见。",
    free="免费",
    free_items=["实时比分、技术统计和积分榜", "后卫、前锋、中锋的百分位排行榜", "包含进阶与基础数据的完整球员档案", "关注你的球队和喜爱的球员"],
    plus_items=["趋势榜：按状态升温或降温为全联盟排名", "最近1周、2周或4周的近期状态", "球员对比和逐年变化", "每场技术统计中的球员评分", "2002-03赛季以来的所有赛季"],
    privacy_line="无需账户，无广告，无追踪。",
    terms="StatScout+ 提供按月或按年订阅（均含7天免费试用），或一次性终身购买。费用将从你的 Apple ID 扣除。订阅会自动续期，除非在当前周期结束前至少24小时取消；可在 Apple ID 设置中管理。",
    privacy_label="隐私政策", terms_label="使用条款（EULA）",
    disclaimer="与NBA及其球队无关联，亦未获其认可。",
)

L["zh-Hant"] = dict(
    name="籃球: " + BRAND,
    subtitle="NBA進階數據與分析",
    keywords="basketball,百分位,球員,比較,排名,比分,直播,技術統計,球隊,戰績",
    promo="免費：即時比分、技術統計、戰績表，以及每位NBA球員的百分位排名。StatScout+ 再加上趨勢榜、近期狀態和球員對比。",
    hook="看清技術統計之外真正的領跑者。",
    intro="StatScout 用分析師使用的數據，將每位NBA球員與同位置組的球員比較：真實命中率、使用率、投籃區域、組織、籃板、防守和場上影響力。每項數據都是一條百分位條，頂尖與掙扎的球員一眼可見。",
    free="免費",
    free_items=["即時比分、技術統計和戰績表", "後衛、前鋒、中鋒的百分位排行榜", "包含進階與基本數據的完整球員檔案", "追蹤你的球隊和喜愛的球員"],
    plus_items=["趨勢榜：依狀態升溫或降溫為全聯盟排名", "最近1週、2週或4週的近期狀態", "球員對比和逐年變化", "每場技術統計中的球員評分", "2002-03球季以來的所有球季"],
    privacy_line="無需帳號，無廣告，無追蹤。",
    terms="StatScout+ 提供按月或按年訂閱（皆含7天免費試用），或一次性終身購買。費用將從你的 Apple ID 扣款。訂閱會自動續訂，除非在目前週期結束前至少24小時取消；可在 Apple ID 設定中管理。",
    privacy_label="隱私權政策", terms_label="使用條款（EULA）",
    disclaimer="與NBA及其球隊無關聯，亦未獲其認可。",
)

L["ar-SA"] = dict(
    name="كرة السلة: " + BRAND,
    subtitle="إحصاءات NBA متقدمة وتحليلات",
    keywords="basketball,مئين,لاعبين,مقارنة,ترتيب,نتائج,مباشر,بوكس سكور,فرق,جدول",
    promo="مجانًا: نتائج مباشرة وبوكس سكور وجداول الترتيب وترتيب مئيني لكل لاعب في NBA. يضيف StatScout+ الاتجاهات والمستوى الحالي ومقارنات اللاعبين.",
    hook="اكتشف من يتصدر بعيدًا عن البوكس سكور.",
    intro="يقارن StatScout كل لاعب في NBA بمجموعة مركزه، بالأرقام التي يستخدمها المحللون: نسبة التسديد الحقيقية، معدل الاستخدام، مناطق التسديد، صناعة اللعب، المتابعات، الدفاع والتأثير داخل الملعب. كل مقياس شريط مئيني، فيظهر النخبة ومن يعانون من النظرة الأولى.",
    free="مجانًا",
    free_items=["نتائج مباشرة وبوكس سكور وجداول الترتيب", "ترتيب مئيني لصانعي الألعاب والأجنحة ولاعبي الارتكاز", "ملفات كاملة للاعبين بإحصاءات متقدمة وتقليدية", "تابع فريقك ولاعبيك المفضلين"],
    plus_items=["الاتجاهات: الدوري كله مرتبًا حسب من يتألق ومن يتراجع", "المستوى الحالي في آخر أسبوع أو أسبوعين أو 4 أسابيع", "مقارنات بين اللاعبين وتطور كل موسم", "تقييم اللاعبين في كل بوكس سكور", "كل المواسم حتى 2002-03"],
    privacy_line="بلا حساب، بلا إعلانات، بلا تتبع.",
    terms="يتوفر StatScout+ باشتراك شهري أو سنوي (كلاهما مع تجربة مجانية لمدة 7 أيام) أو بشراء مدى الحياة لمرة واحدة. يُخصم المبلغ من حساب Apple ID. يتجدد الاشتراك تلقائيًا ما لم يُلغَ قبل 24 ساعة على الأقل من نهاية الفترة؛ يمكنك إدارته من إعدادات Apple ID.",
    privacy_label="الخصوصية", terms_label="شروط الاستخدام (EULA)",
    disclaimer="غير تابع لدوري NBA أو فرقه وغير معتمد منها.",
)

L["he"] = dict(
    name="כדורסל: " + BRAND,
    subtitle="סטטיסטיקות NBA מתקדמות",
    keywords="basketball,אחוזון,שחקנים,השוואה,דירוג,תוצאות,לייב,בוקס סקור,קבוצות,טבלה",
    promo="בחינם: תוצאות חיות, בוקס סקור, טבלאות ודירוג אחוזונים לכל שחקן NBA. ‏StatScout+ מוסיף מגמות, כושר עדכני והשוואות בין שחקנים.",
    hook="גלו מי באמת מוביל מעבר לבוקס סקור.",
    intro="StatScout משווה כל שחקן NBA לקבוצת העמדה שלו, עם המספרים שאנליסטים משתמשים בהם: קליעה אמיתית, שיעור שימוש, אזורי זריקה, בישול, ריבאונד, הגנה והשפעה על המגרש. כל מדד הוא פס אחוזון, כך שהעילית ומי שמתקשה בולטים מיד.",
    free="בחינם",
    free_items=["תוצאות חיות, בוקס סקור וטבלאות", "דירוגי אחוזונים לגארדים, פורוורדים וסנטרים", "פרופילי שחקנים מלאים עם נתונים מתקדמים ורגילים", "עקבו אחרי הקבוצה והשחקנים האהובים עליכם"],
    plus_items=["מגמות: כל הליגה לפי מי בעלייה ומי בירידה", "כושר עדכני בשבוע האחרון, שבועיים או 4 שבועות", "השוואות בין שחקנים והתפתחות משנה לשנה", "ציוני שחקנים בכל בוקס סקור", "כל עונה עד 2002-03"],
    privacy_line="בלי חשבון, בלי פרסומות, בלי מעקב.",
    terms="StatScout+ זמין במנוי חודשי או שנתי (שניהם עם 7 ימי ניסיון חינם) או ברכישה חד־פעמית לכל החיים. החיוב מתבצע דרך ה-Apple ID. המנוי מתחדש אוטומטית אלא אם בוטל לפחות 24 שעות לפני סוף התקופה; ניהול בהגדרות ה-Apple ID.",
    privacy_label="פרטיות", terms_label="תנאי שימוש (EULA)",
    disclaimer="אינו קשור ל-NBA או לקבוצותיה ואינו מאושר על ידן.",
)

L["hi"] = dict(
    name="बास्केटबॉल: " + BRAND,
    subtitle="NBA के एडवांस्ड आँकड़े",
    keywords="basketball,परसेंटाइल,खिलाड़ी,तुलना,रैंकिंग,स्कोर,लाइव,बॉक्स स्कोर,टीम,अंक तालिका",
    promo="मुफ़्त: लाइव स्कोर, बॉक्स स्कोर, अंक तालिका और हर NBA खिलाड़ी की परसेंटाइल रैंकिंग। StatScout+ में ट्रेंड्स, हाल की फ़ॉर्म और खिलाड़ियों की तुलना।",
    hook="बॉक्स स्कोर से आगे देखें कि असल में कौन आगे है।",
    intro="StatScout हर NBA खिलाड़ी को उसकी अपनी पोज़िशन ग्रुप से उन आँकड़ों पर परखता है जो विश्लेषक इस्तेमाल करते हैं: ट्रू शूटिंग, यूसेज, शॉट ज़ोन, प्लेमेकिंग, रिबाउंड, डिफ़ेंस और कोर्ट पर असर। हर आँकड़ा एक परसेंटाइल बार है, इसलिए बेहतरीन और संघर्ष कर रहे खिलाड़ी तुरंत दिखते हैं।",
    free="मुफ़्त",
    free_items=["लाइव स्कोर, बॉक्स स्कोर और अंक तालिका", "गार्ड, फ़ॉरवर्ड और सेंटर के लिए परसेंटाइल रैंकिंग", "एडवांस्ड और सामान्य आँकड़ों के साथ पूरी खिलाड़ी प्रोफ़ाइल", "अपनी टीम और पसंदीदा खिलाड़ियों को फ़ॉलो करें"],
    plus_items=["ट्रेंड्स: पूरी लीग इस हिसाब से कि कौन फ़ॉर्म में है और कौन नहीं", "पिछले 1, 2 या 4 हफ़्तों की फ़ॉर्म", "खिलाड़ियों की आमने-सामने तुलना और साल-दर-साल बदलाव", "हर बॉक्स स्कोर में खिलाड़ियों की रेटिंग", "2002-03 तक का हर सीज़न"],
    privacy_line="कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई ट्रैकिंग नहीं।",
    terms="StatScout+ मासिक या वार्षिक (दोनों में 7 दिन का मुफ़्त ट्रायल) या एक बार की लाइफ़टाइम ख़रीद के रूप में उपलब्ध है। भुगतान आपकी Apple ID से लिया जाता है। सब्सक्रिप्शन अपने-आप रिन्यू होता है जब तक अवधि ख़त्म होने से कम से कम 24 घंटे पहले रद्द न किया जाए; इसे Apple ID सेटिंग्स में मैनेज करें।",
    privacy_label="गोपनीयता", terms_label="उपयोग की शर्तें (EULA)",
    disclaimer="NBA या उसकी टीमों से संबद्ध या उनके द्वारा समर्थित नहीं।",
)

L["id"] = dict(
    name="Basket: " + BRAND,
    subtitle="Statistik NBA lanjutan",
    keywords="basketball,bola basket,persentil,pemain,bandingkan,peringkat,skor,live,box score,klasemen",
    promo="Gratis: skor langsung, box score, klasemen, dan peringkat persentil setiap pemain NBA. StatScout+ menambahkan Tren, performa terkini, dan perbandingan pemain.",
    hook="Lihat siapa yang unggul di luar box score.",
    intro="StatScout membandingkan setiap pemain NBA dengan kelompok posisinya sendiri memakai angka yang dipakai para analis: true shooting, usage, zona tembakan, playmaking, rebound, bertahan, dan dampak di lapangan. Setiap metrik berupa batang persentil, jadi pemain elite dan yang sedang kesulitan langsung terlihat.",
    free="GRATIS",
    free_items=["Skor langsung, box score, dan klasemen", "Peringkat persentil untuk guard, forward, dan center", "Profil pemain lengkap dengan statistik lanjutan dan standar", "Ikuti tim dan pemain favoritmu"],
    plus_items=["Tren: seluruh liga diurutkan menurut siapa yang sedang naik atau turun", "Performa terkini 1, 2, atau 4 minggu terakhir", "Perbandingan pemain dan perkembangan dari tahun ke tahun", "Rating pemain di setiap box score", "Setiap musim hingga 2002-03"],
    privacy_line="Tanpa akun, tanpa iklan, tanpa pelacakan.",
    terms="StatScout+ tersedia bulanan atau tahunan (keduanya dengan uji coba gratis 7 hari) atau pembelian seumur hidup sekali bayar. Pembayaran ditagihkan ke Apple ID Anda. Langganan diperpanjang otomatis kecuali dibatalkan paling lambat 24 jam sebelum periode berakhir; kelola di pengaturan Apple ID.",
    privacy_label="Privasi", terms_label="Ketentuan Penggunaan (EULA)",
    disclaimer="Tidak berafiliasi dengan atau didukung oleh NBA maupun timnya.",
)

L["ms"] = dict(L["id"],
    keywords="basketball,bola keranjang,persentil,pemain,banding,kedudukan,skor,langsung,box score,pasukan",
    promo="Percuma: skor langsung, box score, kedudukan dan ranking persentil setiap pemain NBA. StatScout+ menambah Trend, prestasi terkini dan perbandingan pemain.",
    hook="Lihat siapa yang mendahului di luar box score.",
    intro="StatScout membandingkan setiap pemain NBA dengan kumpulan posisinya sendiri menggunakan angka yang digunakan penganalisis: true shooting, usage, zon jaringan, playmaking, lantunan, pertahanan dan impak di gelanggang. Setiap metrik ialah bar persentil, jadi pemain elit dan yang bergelut kelihatan serta-merta.",
    free="PERCUMA",
    free_items=["Skor langsung, box score dan kedudukan", "Ranking persentil untuk guard, forward dan center", "Profil pemain lengkap dengan statistik lanjutan dan standard", "Ikuti pasukan dan pemain kegemaran anda"],
    plus_items=["Trend: seluruh liga disusun mengikut siapa yang meningkat atau merosot", "Prestasi terkini 1, 2 atau 4 minggu lepas", "Perbandingan pemain dan perkembangan tahun demi tahun", "Penilaian pemain dalam setiap box score", "Setiap musim sehingga 2002-03"],
    privacy_line="Tiada akaun, tiada iklan, tiada penjejakan.",
    terms="StatScout+ ditawarkan bulanan atau tahunan (kedua-duanya dengan percubaan percuma 7 hari) atau pembelian seumur hidup sekali bayar. Bayaran dicaj ke Apple ID anda. Langganan diperbaharui secara automatik melainkan dibatalkan sekurang-kurangnya 24 jam sebelum tempoh tamat; urus dalam tetapan Apple ID.",
    privacy_label="Privasi", terms_label="Terma Penggunaan (EULA)",
    disclaimer="Tidak bergabung dengan atau disokong oleh NBA atau pasukannya.",
)

L["th"] = dict(
    name="บาสเกตบอล: " + BRAND,
    subtitle="สถิติ NBA เชิงลึก",
    keywords="basketball,เปอร์เซ็นไทล์,ผู้เล่น,เปรียบเทียบ,อันดับ,ผลบอล,สด,บ็อกซ์สกอร์,ทีม,ตารางคะแนน",
    promo="ฟรี: ผลสด บ็อกซ์สกอร์ ตารางคะแนน และอันดับเปอร์เซ็นไทล์ของผู้เล่น NBA ทุกคน StatScout+ เพิ่มเทรนด์ ฟอร์มล่าสุด และการเปรียบเทียบผู้เล่น",
    hook="ดูว่าใครโดดเด่นจริงนอกเหนือจากบ็อกซ์สกอร์",
    intro="StatScout เทียบผู้เล่น NBA ทุกคนกับกลุ่มตำแหน่งของตัวเองด้วยตัวเลขที่นักวิเคราะห์ใช้ ได้แก่ ทรูชูตติง อัตราการใช้บอล โซนการยิง การทำเกม รีบาวด์ เกมรับ และอิทธิพลในสนาม ทุกค่าแสดงเป็นแถบเปอร์เซ็นไทล์ ผู้เล่นระดับท็อปและคนที่กำลังฟอร์มตกจึงเห็นได้ทันที",
    free="ฟรี",
    free_items=["ผลสด บ็อกซ์สกอร์ และตารางคะแนน", "อันดับเปอร์เซ็นไทล์ของการ์ด ฟอร์เวิร์ด และเซ็นเตอร์", "โปรไฟล์ผู้เล่นครบทั้งสถิติเชิงลึกและพื้นฐาน", "ติดตามทีมและผู้เล่นคนโปรด"],
    plus_items=["เทรนด์: จัดอันดับทั้งลีกตามว่าใครกำลังฟอร์มขึ้นหรือฟอร์มตก", "ฟอร์มล่าสุด 1, 2 หรือ 4 สัปดาห์", "เปรียบเทียบผู้เล่นตัวต่อตัวและพัฒนาการรายปี", "คะแนนผู้เล่นในทุกบ็อกซ์สกอร์", "ทุกฤดูกาลย้อนหลังถึง 2002-03"],
    privacy_line="ไม่ต้องมีบัญชี ไม่มีโฆษณา ไม่มีการติดตาม",
    terms="StatScout+ มีแบบรายเดือนหรือรายปี (ทั้งสองแบบทดลองใช้ฟรี 7 วัน) หรือซื้อครั้งเดียวใช้ตลอดชีพ การชำระเงินจะเรียกเก็บผ่าน Apple ID ของคุณ การสมัครสมาชิกจะต่ออายุอัตโนมัติ เว้นแต่ยกเลิกอย่างน้อย 24 ชั่วโมงก่อนสิ้นสุดรอบ จัดการได้ในการตั้งค่า Apple ID",
    privacy_label="ความเป็นส่วนตัว", terms_label="ข้อกำหนดการใช้งาน (EULA)",
    disclaimer="ไม่มีส่วนเกี่ยวข้องหรือได้รับการรับรองจาก NBA หรือทีมใดๆ",
)

L["vi"] = dict(
    name="Bóng rổ: " + BRAND,
    subtitle="Thống kê NBA nâng cao",
    keywords="basketball,phân vị,cầu thủ,so sánh,xếp hạng,tỉ số,trực tiếp,box score,đội,bảng xếp hạng",
    promo="Miễn phí: tỉ số trực tiếp, box score, bảng xếp hạng và xếp hạng phân vị cho mọi cầu thủ NBA. StatScout+ thêm Xu hướng, phong độ gần đây và so sánh cầu thủ.",
    hook="Xem ai thực sự dẫn đầu ngoài box score.",
    intro="StatScout so sánh mỗi cầu thủ NBA với chính nhóm vị trí của anh ấy bằng những con số giới phân tích dùng: true shooting, tỉ lệ sử dụng, vùng ném, kiến thiết, bắt bóng bật bảng, phòng ngự và ảnh hưởng trên sân. Mỗi chỉ số là một thanh phân vị, nên cầu thủ hàng đầu và người đang chật vật hiện ra ngay.",
    free="MIỄN PHÍ",
    free_items=["Tỉ số trực tiếp, box score và bảng xếp hạng", "Xếp hạng phân vị cho hậu vệ, tiền phong và trung phong", "Hồ sơ cầu thủ đầy đủ với thống kê nâng cao và cơ bản", "Theo dõi đội bóng và cầu thủ yêu thích"],
    plus_items=["Xu hướng: cả giải xếp theo ai đang lên và ai đang xuống", "Phong độ 1, 2 hoặc 4 tuần gần nhất", "So sánh cầu thủ và tiến triển qua từng mùa", "Điểm đánh giá cầu thủ trong mọi box score", "Mọi mùa giải từ 2002-03"],
    privacy_line="Không tài khoản, không quảng cáo, không theo dõi.",
    terms="StatScout+ có gói tháng hoặc năm (đều được dùng thử miễn phí 7 ngày) hoặc mua một lần dùng trọn đời. Thanh toán qua Apple ID của bạn. Gói đăng ký tự động gia hạn trừ khi hủy ít nhất 24 giờ trước khi kết thúc kỳ; quản lý trong cài đặt Apple ID.",
    privacy_label="Quyền riêng tư", terms_label="Điều khoản sử dụng (EULA)",
    disclaimer="Không liên kết với hay được NBA hoặc các đội bóng chứng thực.",
)

L["ca"] = dict(
    name="Bàsquet: " + BRAND,
    subtitle="Estadístiques avançades NBA",
    keywords="basketball,percentil,jugadors,comparar,classificació,resultats,directe,box score,equips",
    promo="Gratis: resultats en directe, box scores, classificacions i percentils de cada jugador de l'NBA. StatScout+ hi afegeix Tendències, forma recent i duels.",
    hook="Descobreix qui mana més enllà del box score.",
    intro="StatScout compara cada jugador de l'NBA amb el seu propi grup de posició amb els números dels analistes: true shooting, ús, zones de tir, creació, rebot, defensa i impacte a la pista. Cada mètrica és una barra de percentil, així l'elit i els que pateixen es veuen de seguida.",
    free="GRATIS",
    free_items=["Resultats en directe, box scores i classificacions", "Rànquings per percentil per a bases, alers i pivots", "Perfils complets amb estadístiques avançades i clàssiques", "Segueix el teu equip i els teus jugadors preferits"],
    plus_items=["Tendències: tota la lliga ordenada per qui està en ratxa o a la baixa", "Forma recent de l'última setmana, 2 o 4 setmanes", "Duels entre jugadors i evolució any rere any", "Valoració de cada jugador a cada box score", "Totes les temporades des del 2002-03"],
    privacy_line="Sense compte, sense anuncis, sense seguiment.",
    terms="StatScout+ s'ofereix mensual o anual (tots dos amb 7 dies de prova gratuïta) o com a compra única per sempre. El pagament es carrega al teu ID d'Apple. La subscripció es renova automàticament si no es cancel·la com a mínim 24 hores abans del final del període; gestiona-la a la configuració del teu ID d'Apple.",
    privacy_label="Privadesa", terms_label="Condicions d'ús (EULA)",
    disclaimer="Sense afiliació ni aval de l'NBA ni dels seus equips.",
)

ENGLISH_COPIES = ["en-AU", "en-CA", "en-GB"]
PLUS = "STATSCOUT+"
URL_FILES = ["marketing_url.txt", "privacy_url.txt", "support_url.txt"]


def description(d: dict) -> str:
    bullets = lambda items: "\n".join(f"- {item}" for item in items)  # noqa: E731
    return "\n\n".join([
        d["hook"],
        d["intro"],
        f"{d['free']}\n{bullets(d['free_items'])}",
        f"{PLUS}\n{bullets(d['plus_items'])}",
        d["privacy_line"],
        d["terms"],
        f"{d['privacy_label']}: {PRIVACY}\n{d['terms_label']}: {EULA}",
        d["disclaimer"],
    ]) + "\n"


def problems(locale: str, d: dict) -> list[str]:
    out = []
    for field, limit in (("name", 30), ("subtitle", 30), ("keywords", 100), ("promo", 170)):
        if len(d[field]) > limit:
            out.append(f"{locale} {field} {len(d[field])} > {limit}: {d[field]}")
    if len(description(d)) > 4000:
        out.append(f"{locale} description too long")
    words = {w.strip().lower() for w in d["keywords"].split(",")}
    if any("nba" in w for w in words):
        out.append(f"{locale} keywords use a trademark")
    return out


def main() -> int:
    issues = [p for locale, d in L.items() for p in problems(locale, d)]
    for issue in issues:
        print(issue)
    if issues or "--check" in sys.argv:
        return 1 if issues else 0
    source = META / "en-US"
    for locale in ENGLISH_COPIES:
        target = META / locale
        target.mkdir(exist_ok=True)
        for name in ["name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt", "description.txt", *URL_FILES]:
            (target / name).write_text((source / name).read_text())
    for locale, d in L.items():
        target = META / locale
        target.mkdir(exist_ok=True)
        (target / "name.txt").write_text(d["name"] + "\n")
        (target / "subtitle.txt").write_text(d["subtitle"] + "\n")
        (target / "keywords.txt").write_text(d["keywords"] + "\n")
        (target / "promotional_text.txt").write_text(d["promo"] + "\n")
        (target / "description.txt").write_text(description(d))
        for name in URL_FILES:
            (target / name).write_text((source / name).read_text())
    print(f"wrote {len(L) + len(ENGLISH_COPIES)} locales")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
