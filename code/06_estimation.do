/*==============================================================================
  File   : 06_estimation.do
  Input  : $PROC/panel_carburanti_2022.dta, $PROC/costi_daily.dta
  Output : $TAB/risultati_passthrough.dta / .csv   stime di pass-through
           $TAB/event_study_coef.dta               coefficienti degli event study
           $FIG/es_*.png                           grafici degli event study

  Campione: impianti non autostradali, bilanciati nella finestra di marzo,
  prezzi non vecchi. Stime separate per benzina e gasolio.

  Specificazioni
    S1  DiD statico, 1-31 marzo (escluso il 22, giorno di transizione)
    S2  Event study: ogni giorno di marzo rispetto al divario medio di gen-feb
    S3  Come S2 + ritardi del Brent interagiti con l'Italia. I ritardi sono
        stimati solo su gen-feb, quindi i coefficienti di marzo prima del taglio
        sono un test fuori campione: se il Brent spiega il ritardo italiano,
        devono essere vicini a zero.
    S3p Come S3 con la quotazione del prodotto (NY Harbor), se disponibile
    S4  Imputazione: ritardi del Brent stimati su 1/1-21/3 (marzo incluso),
        effetto del taglio = media dei giorni dal 23 al 31 marzo
    S4p Come S4 con la quotazione del prodotto, se disponibile
    S5  Imputazione con un trend lineare italiano stimato sull'1-21 marzo
    S6  Periodi tranquilli: 1/1-23/2 contro 10/4-30/6, taglio continuo
        (30,5 c in Italia, 18 c in Francia); il coefficiente è il pass-through
    S7  Remise francese del 1/4 con l'Italia come controllo (27/3-15/4)

  Pass-through = -(effetto in centesimi) / (taglio in centesimi).
  p_full = p-value di H0: pass-through = 100%.
  Errori standard clusterizzati per provincia (IT) / dipartimento (FR).
  ATTENZIONE: con un solo paese trattato l'incertezza principale riguarda il
  controfattuale, non il campionamento. Gli errori standard dicono quanto è
  precisa la media tra impianti; il confronto tra S1-S7 dice quanto la stima
  dipende dalle ipotesi.
==============================================================================*/

*------------------------------------------------------------------------------
* Pacchetti
*------------------------------------------------------------------------------
foreach p in ftools reghdfe {
    capture which `p'
    if _rc ssc install `p', replace
}

*------------------------------------------------------------------------------
* Date usate qui
*------------------------------------------------------------------------------
global T0_DATA          = $T0_IT + 1     // 23/3: primo giorno trattato nella fotografia delle 8:00
global T0FR_DATA        = $T0_FR + 1     // 2/4: idem per la Francia
global CLEAN_PRE_END    = td(23feb2022)  // fine del periodo tranquillo pre (prima della guerra)
global CLEAN_POST_START = td(10apr2022)  // inizio del periodo tranquillo post
global FR_START         = td(27mar2022)  // S7: dopo l'aggiustamento italiano
global FR_END           = td(15apr2022)

*------------------------------------------------------------------------------
* Programmi di supporto
*------------------------------------------------------------------------------
* Dummy gruppo x giorno, una per ogni giorno con dati del gruppo trattato.
* L'etichetta di ogni dummy contiene il giorno relativo (k = data - ref).
capture program drop make_days
program define make_days, rclass
    syntax, from(integer) to(integer) ref(integer) group(varname) prefix(name) ///
        [omit(integer -99999)]
    capture drop `prefix'm*
    capture drop `prefix'p*
    local list ""
    forvalues d = `from'/`to' {
        if `d' == `omit' continue
        quietly count if `group' == 1 & date == `d'
        if r(N) == 0 continue
        local k = `d' - `ref'
        if `k' < 0 local nm "`prefix'm`=abs(`k')'"
        else       local nm "`prefix'p`k'"
        quietly gen byte `nm' = (`group' == 1 & date == `d')
        label var `nm' "`k'"
        local list "`list' `nm'"
    }
    return local vars "`list'"
end

* Espressione per la media delle dummy con giorno relativo >= kmin
capture program drop avg_expr
program define avg_expr, rclass
    syntax, vars(string) [kmin(integer 1)]
    local sel ""
    foreach v of local vars {
        local k : variable label `v'
        if `k' >= `kmin' local sel "`sel' `v'"
    }
    local n : word count `sel'
    local e = subinstr(trim("`sel'"), " ", " + ", .)
    return local expr "(`e')/`n'"
end

* Salva i coefficienti di un event study
capture program drop post_es
program define post_es
    syntax, vars(string) handle(name) fuel(string) spec(string)
    foreach v of local vars {
        local k : variable label `v'
        capture scalar __b = _b[`v']
        if _rc continue
        post `handle' ("`fuel'") ("`spec'") (`k') (_b[`v']) (_se[`v'])
    }
end

* Salva effetto, pass-through e test di pass-through completo
capture program drop post_pt
program define post_pt
    syntax, handle(name) fuel(string) spec(string) expr(string) cut(real) full(real)
    quietly lincom `expr'
    local b  = r(estimate)
    local se = r(se)
    local p  = 2 * ttail(e(df_r), abs((`b' - (`full')) / `se'))
    post `handle' ("`fuel'") ("`spec'") (`b') (`se') (-`b'/`cut') (`se'/`cut') (`p') (e(N))
    di as result _n "`spec' | `fuel': effetto = " %6.2f `b' " c/l (se " %5.2f `se' ///
        "), pass-through = " %5.3f -`b'/`cut' ", p(H0: 100%) = " %5.3f `p'
end

*------------------------------------------------------------------------------
* Stime
*------------------------------------------------------------------------------
tempname R E
postfile `R' str8 fuel str50 spec double(b se passthrough pt_se p_full N) ///
    using "$TAB/risultati_passthrough.dta", replace
postfile `E' str8 fuel str8 spec int rel_day double(b se) ///
    using "$TAB/event_study_coef.dta", replace

forvalues f = 1/2 {
    local fl   = cond(`f' == 1, "benzina", "gasolio")
    local prod = cond(`f' == 1, "gas", "ulsd")
    di _n as text "{hline 78}" _n "CARBURANTE: `fl'" _n "{hline 78}"

    use if fuel == `f' & balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        using "$PROC/panel_carburanti_2022.dta", clear
    keep unit_id country italy region date price_c tax_cut_c
    gen byte france = 1 - italy
    egen long cl = group(country region), missing

    merge m:1 date using "$PROC/costi_daily.dta", keep(master match) nogen
    foreach c in brent `prod' {
        capture confirm variable `c'_l1
        if _rc continue
        foreach s in l1 l2_7 l8_14 {
            gen double it_`c'_`s' = italy * `c'_`s'
        }
    }
    capture confirm variable it_`prod'_l1
    local has_prod = (_rc == 0)

    *--------------------------------------------------------------------------
    * S1: DiD statico, marzo
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $WIN_START, $EST_END) & date != $T0_IT
        gen byte tp = italy & date >= $T0_DATA
        reghdfe price_c tp, absorb(unit_id date) vce(cluster cl)
        post_pt, handle(`R') fuel(`fl') spec("S1 DiD statico, marzo") ///
            expr(tp) cut($CUT_IT) full(-$CUT_IT)
    restore

    *--------------------------------------------------------------------------
    * S2-S3: event study rispetto a gen-feb, senza e con costi
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $PANEL_START, $EST_END)
        make_days, from($WIN_START) to($EST_END) ref($T0_IT) group(italy) prefix(ev)
        local evs "`r(vars)'"
        avg_expr, vars(`evs') kmin(1)
        local pexp "`r(expr)'"

        reghdfe price_c `evs', absorb(unit_id date) vce(cluster cl)
        post_es, vars(`evs') handle(`E') fuel(`fl') spec("S2")
        post_pt, handle(`R') fuel(`fl') spec("S2 ES vs gen-feb, senza costi") ///
            expr(`pexp') cut($CUT_IT) full(-$CUT_IT)

        reghdfe price_c `evs' it_brent_*, absorb(unit_id date) vce(cluster cl)
        post_es, vars(`evs') handle(`E') fuel(`fl') spec("S3")
        post_pt, handle(`R') fuel(`fl') spec("S3 ES vs gen-feb, Brent stimato su gen-feb") ///
            expr(`pexp') cut($CUT_IT) full(-$CUT_IT)

        if `has_prod' {
            reghdfe price_c `evs' it_`prod'_*, absorb(unit_id date) vce(cluster cl)
            post_es, vars(`evs') handle(`E') fuel(`fl') spec("S3p")
            post_pt, handle(`R') fuel(`fl') spec("S3p ES vs gen-feb, prodotto NYH su gen-feb") ///
                expr(`pexp') cut($CUT_IT) full(-$CUT_IT)
        }
    restore

    *--------------------------------------------------------------------------
    * S4: imputazione con costi stimati su 1/1-21/3
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $PANEL_START, $EST_END)
        make_days, from($T0_IT) to($EST_END) ref($T0_IT) group(italy) prefix(ev)
        local evs "`r(vars)'"
        avg_expr, vars(`evs') kmin(1)
        local pexp "`r(expr)'"

        reghdfe price_c `evs' it_brent_*, absorb(unit_id date) vce(cluster cl)
        post_es, vars(`evs') handle(`E') fuel(`fl') spec("S4")
        post_pt, handle(`R') fuel(`fl') spec("S4 imputazione, Brent su 1/1-21/3") ///
            expr(`pexp') cut($CUT_IT) full(-$CUT_IT)

        if `has_prod' {
            reghdfe price_c `evs' it_`prod'_*, absorb(unit_id date) vce(cluster cl)
            post_es, vars(`evs') handle(`E') fuel(`fl') spec("S4p")
            post_pt, handle(`R') fuel(`fl') spec("S4p imputazione, prodotto NYH su 1/1-21/3") ///
                expr(`pexp') cut($CUT_IT) full(-$CUT_IT)
        }
    restore

    *--------------------------------------------------------------------------
    * S5: imputazione con trend lineare italiano (1-21 marzo)
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $WIN_START, $EST_END)
        gen double t_it = italy * (date - $T0_IT)
        make_days, from($T0_IT) to($EST_END) ref($T0_IT) group(italy) prefix(ev)
        local evs "`r(vars)'"
        avg_expr, vars(`evs') kmin(1)
        local pexp "`r(expr)'"

        reghdfe price_c `evs' t_it, absorb(unit_id date) vce(cluster cl)
        post_es, vars(`evs') handle(`E') fuel(`fl') spec("S5")
        post_pt, handle(`R') fuel(`fl') spec("S5 imputazione, trend lineare marzo") ///
            expr(`pexp') cut($CUT_IT) full(-$CUT_IT)
    restore

    *--------------------------------------------------------------------------
    * S6: periodi tranquilli, taglio continuo
    *--------------------------------------------------------------------------
    preserve
        keep if date <= $CLEAN_PRE_END | inrange(date, $CLEAN_POST_START, $PANEL_END)
        reghdfe price_c tax_cut_c, absorb(unit_id date) vce(cluster cl)
        post_pt, handle(`R') fuel(`fl') spec("S6 periodi tranquilli, taglio continuo") ///
            expr(tax_cut_c) cut(1) full(-1)
    restore

    *--------------------------------------------------------------------------
    * S7: remise francese, Italia come controllo
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $FR_START, $FR_END) & date != $T0_FR
        gen byte tp = france & date >= $T0FR_DATA
        reghdfe price_c tp, absorb(unit_id date) vce(cluster cl)
        post_pt, handle(`R') fuel(`fl') spec("S7 remise FR, DiD statico") ///
            expr(tp) cut($CUT_FR) full(-$CUT_FR)

        make_days, from($FR_START) to($FR_END) ref($T0_FR) group(france) ///
            prefix(fr) omit(`=$T0_FR - 1')
        local frs "`r(vars)'"
        reghdfe price_c `frs', absorb(unit_id date) vce(cluster cl)
        post_es, vars(`frs') handle(`E') fuel(`fl') spec("S7")
    restore
}

postclose `R'
postclose `E'

*------------------------------------------------------------------------------
* Tabella dei risultati
*------------------------------------------------------------------------------
use "$TAB/risultati_passthrough.dta", clear
format b se passthrough pt_se p_full %9.3f
format N %12.0fc
list fuel spec b se passthrough pt_se p_full N, sep(0) noobs abbreviate(12)
export delimited using "$TAB/risultati_passthrough.csv", replace

*------------------------------------------------------------------------------
* Grafici degli event study
*------------------------------------------------------------------------------
use "$TAB/event_study_coef.dta", clear
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se

local t_S2  "Senza controlli per i costi (rif.: divario medio gen-feb)"
local t_S3  "Con Brent, ritardi stimati su gen-feb (rif.: gen-feb)"
local t_S3p "Con prodotto NYH, ritardi stimati su gen-feb (rif.: gen-feb)"
local t_S4  "Imputazione con Brent (ritardi stimati su 1/1-21/3)"
local t_S4p "Imputazione con prodotto NYH (ritardi stimati su 1/1-21/3)"
local t_S5  "Imputazione con trend lineare (1-21 marzo)"

foreach s in S2 S3 S3p S4 S4p S5 {
    foreach fl in benzina gasolio {
        quietly count if spec == "`s'" & fuel == "`fl'"
        if r(N) == 0 continue
        twoway (rcap hi lo rel_day if spec == "`s'" & fuel == "`fl'", lcolor(navy%60)) ///
               (scatter b rel_day if spec == "`s'" & fuel == "`fl'", mcolor(navy) msize(small)), ///
            yline(0, lcolor(gs10)) yline(-$CUT_IT, lpattern(dash) lcolor(maroon)) ///
            xline(-0.5, lpattern(dash) lcolor(gs6)) ///
            title("`fl': event study `s'") subtitle("`t_`s''") ///
            xtitle("giorni dal taglio (0 = 22/3, solo in parte trattato)") ///
            ytitle("Italia - Francia, centesimi/l") legend(off) ///
            note("Linea rossa: taglio con IVA (-$CUT_IT c/l). Intervalli al 95%.")
        graph export "$FIG/es_`s'_`fl'.png", replace width(2000)
    }
}

foreach fl in benzina gasolio {
    twoway (rcap hi lo rel_day if spec == "S7" & fuel == "`fl'", lcolor(maroon%60)) ///
           (scatter b rel_day if spec == "S7" & fuel == "`fl'", mcolor(maroon) msize(small)), ///
        yline(0, lcolor(gs10)) yline(-$CUT_FR, lpattern(dash) lcolor(navy)) ///
        xline(-0.5, lpattern(dash) lcolor(gs6)) ///
        title("`fl': remise francese, Italia come controllo") ///
        xtitle("giorni dalla remise (0 = 1/4, solo in parte trattato; rif. = 31/3)") ///
        ytitle("Francia - Italia, centesimi/l") legend(off) ///
        note("Linea blu: remise con IVA (-$CUT_FR c/l). Intervalli al 95%.")
    graph export "$FIG/es_S7_`fl'.png", replace width(2000)
}
