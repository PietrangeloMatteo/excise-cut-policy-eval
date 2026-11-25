/*==============================================================================
  File   : 99_tests.do
  Scopo  : controlli automatici su dati, stime e output. Non si ferma al primo
           errore: stampa PASS/FAIL per ogni controllo e un riepilogo finale.
  Uso    : lanciare dal master (RUN_TESTS = 1) dopo aver eseguito 01-09.

  I valori di riferimento vengono dai log dell'11 novembre 2026. Se cambi
  campione o parametri nel master, i controlli "numerici" (sezione E) falliranno
  per costruzione: aggiorna le costanti solo dopo aver capito perché cambiano.

  Confronto con una versione precedente (facoltativo): copia la cartella
  output/tables in output/tables_ref PRIMA di rieseguire la pipeline; la
  sezione G confronta i risultati nuovi con quelli salvati.
==============================================================================*/

global NPASS = 0
global NFAIL = 0

capture program drop check
program define check
    args rc msg
    if `rc' == 0 {
        di as result "PASS  " as text "`msg'"
        global NPASS = $NPASS + 1
    }
    else {
        di as error  "FAIL  `msg'"
        global NFAIL = $NFAIL + 1
    }
end

local tol = 0.01      // tolleranza in centesimi per i controlli numerici

*==============================================================================
* A. File prodotti dalla pipeline
*==============================================================================
di _n as text "{hline 78}" _n "A. File attesi" _n "{hline 78}"
foreach f in "$TEMP/italy_clean.dta" "$TEMP/france_clean.dta" ///
             "$PROC/panel_carburanti_2022.dta" "$PROC/costi_daily.dta" ///
             "$TAB/risultati_passthrough.dta" "$TAB/event_study_coef.dta" ///
             "$TAB/event_study_rif21.dta" "$TAB/event_study_ref18.dta" ///
             "$TAB/tab_descriptive.tex" "$TAB/tab_results.tex" "$TAB/tab_es_ref18.tex" {
    capture confirm file "`f'"
    check `=_rc' "esiste `f'"
}
foreach fl in petrol diesel {
    foreach g in prices_`fl' es_ref21_`fl' es_ref18_`fl' hd_sd_g2_`fl' hd_rm_g2_`fl' es_S7_`fl' {
        capture confirm file "$OUT/figures_en/fig_`g'.png"
        check `=_rc' "esiste figura fig_`g'.png"
    }
}

*==============================================================================
* B. Struttura del panel
*==============================================================================
di _n as text "{hline 78}" _n "B. Panel" _n "{hline 78}"
use "$PROC/panel_carburanti_2022.dta", clear

capture isid unit_id date
check `=_rc' "unit_id x date identifica le osservazioni"

capture assert inlist(country, 1, 2) & inlist(fuel, 1, 2)
check `=_rc' "country e fuel assumono solo i valori 1 e 2"

capture assert inrange(price, $PMIN, $PMAX) if !missing(price)
check `=_rc' "prezzi non mancanti dentro [$PMIN, $PMAX] euro/l"

capture assert inrange(date, $PANEL_START, $PANEL_END)
check `=_rc' "date dentro il periodo del panel"

capture assert days_since_update >= 0 if !missing(days_since_update)
check `=_rc' "nessuna data di aggiornamento successiva alla data del prezzo"

capture assert strpos(upper(comune), "LIVIGNO") == 0 if country == 1
check `=_rc' "Livigno escluso"

capture assert !inlist(region, "20", "97", "98") if country == 2
check `=_rc' "Corsica e oltremare esclusi"

capture assert tax_cut_c == 0 if date < $T0_IT
check `=_rc' "nessun taglio fiscale prima del 22 marzo"

capture assert tax_cut_c == $CUT_IT if country == 1 & date >= $T0_IT
check `=_rc' "taglio italiano = $CUT_IT dal 22 marzo"

capture assert tax_cut_c == $CUT_FR if country == 2 & date >= $T0_FR
check `=_rc' "remise francese = $CUT_FR dal 1 aprile"

* giorni con dati nella finestra 1-26 marzo: 24 in Italia (mancano 15-16), 26 in Francia
preserve
    keep if inrange(date, $WIN_START, $WIN_END)
    bysort country date: keep if _n == 1
    quietly count if country == 1
    check `=r(N) != 24' "Italia: 24 giorni con dati nella finestra (trovati `r(N)')"
    quietly count if country == 2
    check `=r(N) != 26' "Francia: 26 giorni con dati nella finestra (trovati `r(N)')"
    quietly count if country == 1 & inlist(date, td(15mar2022), td(16mar2022))
    check `=r(N) != 0' "Italia: 15 e 16 marzo assenti"
restore

* campione di stima: unità e cluster (valori da 09_announcement.do)
preserve
    keep if balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        & inrange(date, $WIN_START, $EST_END)
    bysort unit_id: keep if _n == 1
    local exp_1_1 = 16879
    local exp_1_2 = 3654
    local exp_2_1 = 16816
    local exp_2_2 = 8699
    forvalues f = 1/2 {
        forvalues c = 1/2 {
            quietly count if fuel == `f' & country == `c'
            check `=r(N) != `exp_`f'_`c''' "unità fuel `f' country `c' = `exp_`f'_`c'' (trovate `r(N)')"
        }
    }
    egen long cl = group(country region), missing
    quietly levelsof cl, local(lv)
    local ncl : word count `lv'
    check `=`ncl' != 205' "205 cluster provincia/dipartimento (trovati `ncl')"
restore

*==============================================================================
* C. Serie di costo
*==============================================================================
di _n as text "{hline 78}" _n "C. Costi" _n "{hline 78}"
use "$PROC/costi_daily.dta", clear
capture assert !missing(brent, brent_l1, brent_l2_7, brent_l8_14) if date >= $PANEL_START
check `=_rc' "Brent e ritardi presenti dall'inizio del panel"
capture assert inrange(brent, 30, 100) if date >= $PANEL_START
check `=_rc' "Brent tra 30 e 100 centesimi/l nel 2022"
capture isid date
check `=_rc' "una sola osservazione per giorno"

*==============================================================================
* D. Coerenza economica dei dati grezzi
*==============================================================================
di _n as text "{hline 78}" _n "D. Salti attesi nel divario Italia-Francia" _n "{hline 78}"
use "$PROC/panel_carburanti_2022.dta", clear
keep if balanced == 1 & highway != 1 & !stale & !missing(price_c)
collapse (mean) price_c, by(country fuel date)
reshape wide price_c, i(fuel date) j(country)
gen gap = price_c1 - price_c2
tsset fuel date
gen d_it = gap - L3.gap if date == $T0_IT + 2      // 21 -> 24 marzo
gen d_fr = gap - L2.gap if date == $T0_FR + 1      // 31 marzo -> 2 aprile
forvalues f = 1/2 {
    quietly summarize d_it if fuel == `f', meanonly
    check `=!inrange(r(mean), -40, -20)' "fuel `f': divario 21-24 marzo cala di 20-40 c (`: di %5.1f r(mean)')"
    quietly summarize d_fr if fuel == `f', meanonly
    check `=!inrange(r(mean), 8, 25)' "fuel `f': divario 31 mar-2 apr sale di 8-25 c (`: di %5.1f r(mean)')"
}

*==============================================================================
* E. Riproduzione delle stime (valori dei log dell'11/11/2026)
*==============================================================================
di _n as text "{hline 78}" _n "E. Stime salvate" _n "{hline 78}"
use "$TAB/risultati_passthrough.dta", clear
gen code = word(spec, 1)
quietly count
check `=r(N) != 18' "18 righe nella tabella dei risultati (trovate `r(N)')"
foreach x in "benzina S1 -26.57232" "gasolio S1 -29.53463" ///
             "benzina S2 -21.16513" "gasolio S2 -25.82171" ///
             "benzina S7 -14.15765" "gasolio S7 -21.44507" {
    tokenize `x'
    quietly summarize b if fuel == "`1'" & code == "`2'", meanonly
    check `=abs(r(mean) - (`3')) > `tol'' "`1' `2': effetto `3' (trovato `: di %9.4f r(mean)')"
}

use "$TAB/event_study_rif21.dta", clear
foreach x in "benzina 2 -28.65245" "gasolio 2 -35.47905" "benzina -5 4.192376" {
    tokenize `x'
    quietly summarize b if fuel == "`1'" & rel_day == `2', meanonly
    check `=abs(r(mean) - (`3')) > `tol'' "rif. 21/3, `1' giorno `2': `3' (trovato `: di %9.4f r(mean)')"
}
quietly count if rel_day == -1
check `=r(N) != 0' "rif. 21/3: nessun coefficiente per il giorno di riferimento"

use "$TAB/event_study_ref18.dta", clear
foreach x in "petrol 2 -32.38965" "diesel 2 -40.94749" "petrol -5 .4551726" {
    tokenize `x'
    quietly summarize b if fuel == "`1'" & rel_day == `2', meanonly
    check `=abs(r(mean) - (`3')) > `tol'' "rif. 18/3, `1' giorno `2': `3' (trovato `: di %9.4f r(mean)')"
}
quietly count if rel_day == -4
check `=r(N) != 0' "rif. 18/3: nessun coefficiente per il giorno di riferimento"

*==============================================================================
* F. Ristima indipendente di S1 (controlla che la regressione sia riproducibile)
*==============================================================================
di _n as text "{hline 78}" _n "F. Ristima di S1" _n "{hline 78}"
local s1_1 = -26.57232
local s1_2 = -29.53463
forvalues f = 1/2 {
    use if fuel == `f' & balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        & inrange(date, $WIN_START, $EST_END) & date != $T0_IT ///
        using "$PROC/panel_carburanti_2022.dta", clear
    egen long cl = group(country region), missing
    gen byte tp = italy & date >= $T0_IT + 1
    quietly reghdfe price_c tp, absorb(unit_id date) vce(cluster cl)
    check `=abs(_b[tp] - (`s1_`f'')) > `tol'' "S1 fuel `f' ristimato: `s1_`f'' (trovato `: di %9.4f _b[tp]')"
    check `=e(N_clust) != 205' "S1 fuel `f': 205 cluster (trovati `e(N_clust)')"
}

*==============================================================================
* G. Confronto con una versione precedente (se esiste output/tables_ref)
*==============================================================================
capture confirm file "$OUT/tables_ref/risultati_passthrough.dta"
if !_rc {
    di _n as text "{hline 78}" _n "G. Confronto con output/tables_ref" _n "{hline 78}"
    use "$OUT/tables_ref/risultati_passthrough.dta", clear
    rename (b se passthrough) (b_old se_old pt_old)
    keep fuel spec b_old se_old pt_old
    merge 1:1 fuel spec using "$TAB/risultati_passthrough.dta", keepusing(b se passthrough)
    capture assert _merge == 3
    check `=_rc' "stesse specificazioni nella versione vecchia e nuova"
    capture assert abs(b - b_old) < 1e-6 & abs(se - se_old) < 1e-6 if _merge == 3
    check `=_rc' "stime identiche alla versione precedente"
}

*==============================================================================
* Riepilogo
*==============================================================================
di _n as text "{hline 78}"
di as text "Controlli superati: " as result $NPASS as text "   falliti: " as error $NFAIL
di as text "{hline 78}"
