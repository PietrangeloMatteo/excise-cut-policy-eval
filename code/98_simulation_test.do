/*==============================================================================
  File   : 98_simulation_test.do
  Scopo  : verificare che il codice di stima recuperi un pass-through NOTO.
           Costruisce un panel simulato con la stessa struttura di quello vero,
           lo salva in una cartella separata (ROOT/sim/...), fa girare gli
           script veri 06, 07 e 09 su quei dati e confronta le stime con i
           valori impostati. I dati e i risultati veri non vengono toccati.

  Processo generatore (prezzo in centesimi/l, impianto i, giorno t):
     P_it = alpha_i + lambda_ft + effetto_it + trend_it + e_it
     alpha_i    effetto fisso di impianto, N(0, 5) + N(0, 2) per carburante
     lambda_ft  shock comune ai due paesi: random walk con passi N(0, 1.5)
     e_it       rumore N(0, 2)
     effetto    Italia: 25% del taglio il 22/3, taglio pieno dal 23/3
                Francia: 25% della remise il 1/4, remise piena dal 2/4
     trend      solo scenario B: trend lineare italiano dal 1/3 (SIM_TREND
                centesimi al giorno), che prosegue anche dopo il taglio

  Scenario A: trend paralleli veri. Tutte le specificazioni devono recuperare
              i pass-through impostati (S6 recupera una combinazione nota).
  Scenario B: trend paralleli violati da un trend lineare noto. S5 (che stima
              il trend) deve recuperare il valore vero; S1 e l'event study
              devono essere distorti esattamente della quantità prevista.

  Come nei dati veri, l'Italia non ha osservazioni il 15 e 16 marzo.
  honestdid (07) gira ma i suoi intervalli vanno controllati a mano nel log:
  il valore vero da confrontare viene stampato prima dei controlli.
==============================================================================*/

*------------------------------------------------------------------------------
* Parametri veri
*------------------------------------------------------------------------------
global SIM_RHO_IT1 = 0.80     // pass-through italiano, benzina
global SIM_RHO_IT2 = 0.95     // pass-through italiano, gasolio
global SIM_RHO_FR1 = 0.70     // pass-through francese, benzina
global SIM_RHO_FR2 = 0.90     // pass-through francese, gasolio
global SIM_TREND   = -1       // scenario B: centesimi al giorno, solo Italia
global SIM_NIT     = 1000     // impianti italiani
global SIM_NFR     = 500      // impianti francesi
local  tol_pt      = 0.02     // tolleranza sul pass-through
local  tol_c       = 0.5      // tolleranza in centesimi

*------------------------------------------------------------------------------
* Programma: controllo con conteggio
*------------------------------------------------------------------------------
global SIM_PASS = 0
global SIM_FAIL = 0
capture program drop simcheck
program define simcheck
    args found expected tol msg
    local ok = abs(`found' - (`expected')) <= `tol'
    local fs : di %8.4f `found'
    local es : di %8.4f `expected'
    if `ok' {
        di as result "PASS  " as text "`msg': trovato `fs', atteso `es'"
        global SIM_PASS = $SIM_PASS + 1
    }
    else {
        di as error  "FAIL  `msg': trovato `fs', atteso `es'"
        global SIM_FAIL = $SIM_FAIL + 1
    }
end

*------------------------------------------------------------------------------
* Programma: costruzione del panel simulato
*------------------------------------------------------------------------------
capture program drop sim_build
program define sim_build
    syntax, scenario(string) [seed(integer 20220322)]
    set seed `seed'
    local nd = $PANEL_END - $PANEL_START + 1

    * shock comune per carburante (random walk)
    clear
    set obs `nd'
    gen date = $PANEL_START + _n - 1
    expand 2
    bysort date: gen byte fuel = _n
    sort fuel date
    gen double lambda = rnormal(0, 1.5)
    by fuel: replace lambda = 170 + sum(lambda)
    tempfile common
    save `common'

    * impianti
    clear
    set obs `=$SIM_NIT + $SIM_NFR'
    gen long station_id = _n
    gen byte country = cond(_n <= $SIM_NIT, 1, 2)
    gen byte italy = country == 1
    gen str3 region = cond(italy, "P" + string(mod(_n, 20) + 1, "%02.0f"), ///
                                  "D" + string(mod(_n, 15) + 1, "%02.0f"))
    gen double alpha_s = rnormal(0, 5)
    expand 2
    bysort station_id: gen byte fuel = _n
    gen double alpha = alpha_s + rnormal(0, 2)
    egen long unit_id = group(station_id fuel)
    expand `nd'
    bysort unit_id: gen date = $PANEL_START + _n - 1
    merge m:1 fuel date using `common', nogen

    * effetti veri
    gen double rho_it = cond(fuel == 1, $SIM_RHO_IT1, $SIM_RHO_IT2)
    gen double rho_fr = cond(fuel == 1, $SIM_RHO_FR1, $SIM_RHO_FR2)
    gen double eff = 0
    replace eff = -0.25 * rho_it * $CUT_IT if italy  & date == $T0_IT
    replace eff = -rho_it * $CUT_IT        if italy  & date >  $T0_IT
    replace eff = -0.25 * rho_fr * $CUT_FR if !italy & date == $T0_FR
    replace eff = -rho_fr * $CUT_FR        if !italy & date >  $T0_FR

    gen double trend = 0
    if "`scenario'" == "B" {
        replace trend = $SIM_TREND * (date - $WIN_START) if italy & date >= $WIN_START
    }

    gen double price_c = alpha + lambda + eff + trend + rnormal(0, 2)

    * stessa struttura del panel vero
    drop if italy & inlist(date, td(15mar2022), td(16mar2022))
    gen double price     = price_c / 100
    gen double tax_cut_c = 0
    replace tax_cut_c = $CUT_IT if italy  & date >= $T0_IT
    replace tax_cut_c = $CUT_FR if !italy & date >= $T0_FR
    gen byte stale    = 0
    gen byte highway  = 0
    gen byte balanced = 1
    format date %td
    keep unit_id station_id country italy fuel region date price price_c ///
         tax_cut_c stale highway balanced
    compress
    save "$PROC/panel_carburanti_2022.dta", replace
end

*------------------------------------------------------------------------------
* Esecuzione dei due scenari con gli script veri
*------------------------------------------------------------------------------
foreach g in PROC TAB OUT FIG FIGEN {
    global `g'_REAL "$`g'"
}

capture mkdir "$ROOT/sim"
local rc_all = 0
foreach sc in A B {
    di _n as text "{hline 78}" _n "SCENARIO `sc': costruzione dati e stime" _n "{hline 78}"
    global PROC "$ROOT/sim/`sc'/processed"
    global TAB  "$ROOT/sim/`sc'/tables"
    global OUT  "$ROOT/sim/`sc'/output"
    global FIG  "$OUT/figures"
    foreach d in "$ROOT/sim/`sc'" "$PROC" "$TAB" "$OUT" "$FIG" {
        capture mkdir "`d'"
    }
    sim_build, scenario(`sc')
    copy "$PROC_REAL/costi_daily.dta" "$PROC/costi_daily.dta", replace

    foreach s in 06_estimation 07_honestdid 09_announcement {
        capture noisily do "$CODE/`s'.do"
        if _rc {
            di as error "Scenario `sc': `s'.do si è fermato con errore `=_rc'"
            local rc_all = _rc
        }
    }
}

* ripristino dei percorsi veri, anche se qualcosa è andato storto
foreach g in PROC TAB OUT FIG FIGEN {
    global `g' "$`g'_REAL"
}
if `rc_all' {
    di as error "Almeno uno script si è fermato: i controlli sotto possono fallire per questo."
}

*==============================================================================
* Controlli: scenario A (trend paralleli veri)
*==============================================================================
local SA "$ROOT/sim/A/tables"
di _n as text "{hline 78}" _n "CONTROLLI SCENARIO A" _n "{hline 78}"

forvalues f = 1/2 {
    local fl  = cond(`f' == 1, "benzina", "gasolio")
    local fe  = cond(`f' == 1, "petrol", "diesel")
    local rit = ${SIM_RHO_IT`f'}
    local rfr = ${SIM_RHO_FR`f'}
    local s6  = ($CUT_IT * `rit' - $CUT_FR * `rfr') / ($CUT_IT - $CUT_FR)

    di _n as text "--- `fl': pass-through vero Italia = `rit', Francia = `rfr'"
    di as text "    honestdid (log di 07, scenario A): con Mbar = 0 e M = 0 l'intervallo" ///
        " per il giorno +2 deve contenere `: di %6.2f -`rit' * $CUT_IT' centesimi"

    use "`SA'/risultati_passthrough.dta", clear
    gen code = word(spec, 1)
    foreach c in S1 S2 S3 S3p S4 S4p S5 {
        quietly summarize passthrough if fuel == "`fl'" & code == "`c'", meanonly
        if r(N) simcheck `r(mean)' `rit' `tol_pt' "`fl' `c' pass-through"
    }
    quietly summarize passthrough if fuel == "`fl'" & code == "S6", meanonly
    simcheck `r(mean)' `s6' `tol_pt' "`fl' S6 = (30,5 rho_IT - 18 rho_FR) / 12,5"
    quietly summarize passthrough if fuel == "`fl'" & code == "S7", meanonly
    simcheck `r(mean)' `rfr' `tol_pt' "`fl' S7 pass-through francese"

    use "`SA'/event_study_rif21.dta", clear
    quietly summarize b if fuel == "`fl'" & rel_day == 2, meanonly
    simcheck `r(mean)' `=-`rit' * $CUT_IT' `tol_c' "`fl' rif. 21/3, giorno +2 (c/l)"
    quietly summarize b if fuel == "`fl'" & rel_day == 0, meanonly
    simcheck `r(mean)' `=-0.25 * `rit' * $CUT_IT' `tol_c' "`fl' rif. 21/3, giorno 0 (25% del taglio)"
    quietly summarize b if fuel == "`fl'" & rel_day < -1
    simcheck `=max(abs(r(min)), abs(r(max)))' 0 `tol_c' "`fl' rif. 21/3, massimo |pre-trend|"

    use "`SA'/passthrough_ref18.dta", clear
    quietly summarize passthrough if fuel == "`fe'" & target == "avg 23-31 Mar", meanonly
    simcheck `r(mean)' `rit' `tol_pt' "`fl' rif. 18/3, media 23-31 marzo"
    quietly summarize passthrough if fuel == "`fe'" & target == "day -1", meanonly
    simcheck `r(mean)' 0 `tol_pt' "`fl' rif. 18/3, 21 marzo (nessun effetto annuncio)"
}

*==============================================================================
* Controlli: scenario B (trend italiano lineare noto)
*==============================================================================
local SB "$ROOT/sim/B/tables"
di _n as text "{hline 78}" _n "CONTROLLI SCENARIO B (trend = $SIM_TREND c/giorno)" _n "{hline 78}"

* S1: media post (23-31/3) meno media pre (1-21/3 senza 15-16) del trend
*     trend(t) = SIM_TREND * (t - 1 marzo), cioè SIM_TREND * (k + 21)
local post = 0
forvalues k = 1/9 {
    local post = `post' + (`k' + 21) / 9
}
local pre = 0
local npre = 0
forvalues k = -21/-1 {
    if inlist(`k', -7, -6) continue
    local pre = `pre' + `k' + 21
    local ++npre
}
local s1_bias = $SIM_TREND * (`post' - `pre' / `npre')

forvalues f = 1/2 {
    local fl  = cond(`f' == 1, "benzina", "gasolio")
    local fe  = cond(`f' == 1, "petrol", "diesel")
    local rit = ${SIM_RHO_IT`f'}

    di _n as text "--- `fl': pass-through vero Italia = `rit'"
    di as text "    honestdid (log di 07, scenario B): con smoothness M = 0 l'intervallo" ///
        " per il giorno +2 deve contenere `: di %6.2f -`rit' * $CUT_IT' centesimi"

    use "`SB'/risultati_passthrough.dta", clear
    gen code = word(spec, 1)
    quietly summarize passthrough if fuel == "`fl'" & code == "S5", meanonly
    simcheck `r(mean)' `rit' `tol_pt' "`fl' S5 (trend stimato) recupera il valore vero"
    quietly summarize b if fuel == "`fl'" & code == "S1", meanonly
    simcheck `r(mean)' `=-`rit' * $CUT_IT + `s1_bias'' `tol_c' "`fl' S1 distorto della quantità prevista (c/l)"

    use "`SB'/event_study_rif21.dta", clear
    quietly summarize b if fuel == "`fl'" & rel_day == 2, meanonly
    simcheck `r(mean)' `=-`rit' * $CUT_IT + 3 * $SIM_TREND' `tol_c' "`fl' rif. 21/3, giorno +2 = effetto + 3 x trend"
    quietly summarize b if fuel == "`fl'" & rel_day == -5, meanonly
    simcheck `r(mean)' `=-4 * $SIM_TREND' `tol_c' "`fl' rif. 21/3, giorno -5 = -4 x trend"

    use "`SB'/passthrough_ref18.dta", clear
    quietly summarize b if fuel == "`fe'" & target == "day 2", meanonly
    simcheck `r(mean)' `=-`rit' * $CUT_IT + 6 * $SIM_TREND' `tol_c' "`fl' rif. 18/3, giorno +2 = effetto + 6 x trend"
}

*==============================================================================
* Riepilogo
*==============================================================================
di _n as text "{hline 78}"
di as text "Simulazione - controlli superati: " as result $SIM_PASS ///
   as text "   falliti: " as error $SIM_FAIL
di as text "{hline 78}"
