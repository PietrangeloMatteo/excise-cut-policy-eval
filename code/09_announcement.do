/*==============================================================================
  File   : 09_announcement.do
  Input  : $PROC/panel_carburanti_2022.dta
  Output : $TAB/cluster_check.dta / .csv     cluster per paese e carburante
           $TAB/event_study_ref18.dta        coefficienti (rif. 18 marzo)
           $TAB/passthrough_ref18.dta / .csv effetti e pass-through per giorno
           $TAB/tab_es_ref18.tex             tabella per il paper
           $OUT/figures_en/fig_es_ref18_<fuel>.png

  Cosa cambia rispetto a 07: il giorno di riferimento è il 18 marzo invece del
  21. Il prezzo delle 8:00 del 18 marzo precede l'approvazione del decreto
  (sera del 18), quindi è l'ultimo giorno non influenzato dall'annuncio.
  I coefficienti dal 19 marzo in poi misurano annuncio + attuazione insieme.
  Le specificazioni S1-S7 e lo script 07 non sono modificati.

  Giorni relativi: k = data - 22 marzo, come negli altri script.
    k <= -5        prima dell'annuncio (1-17 marzo; 15-16 mancanti)
    k = -4         18 marzo, riferimento
    k = -3..-1     19-21 marzo: dopo l'annuncio, prima dell'entrata in vigore
    k = 0          22 marzo, solo in parte trattato
    k = 1..9       23-31 marzo

  honestdid NON viene lanciato qui: con riferimento 18 marzo i giorni di
  calibrazione pre-annuncio sarebbero 17, 14, 13, ... marzo, non consecutivi
  perché il 15 e il 16 mancano nell'archivio MIMIT. Il metodo assume periodi
  equidistanti, quindi la calibrazione non sarebbe valida. Va rifatta solo se
  si recuperano i due file mancanti.

  Cluster: `region' contiene la sigla della provincia (Italia, dall'anagrafica
  MIMIT) e il numero del dipartimento (Francia, prime due cifre del codice
  postale). Il blocco A conta i cluster per paese.
==============================================================================*/

foreach p in ftools reghdfe {
    capture which `p'
    if _rc ssc install `p', replace
}

global T_ANN = td(18mar2022)      // riferimento: ultimo prezzo delle 8:00 pre-annuncio
global FIGEN "$OUT/figures_en"
capture mkdir "$FIGEN"
set scheme s1color

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

tempname C E P
postfile `C' str8 fuel str8 country long(n_clusters n_units n_units_noregion) ///
    using "$TAB/cluster_check.dta", replace
postfile `E' str8 fuel int rel_day double(b se) ///
    using "$TAB/event_study_ref18.dta", replace
postfile `P' str8 fuel str24 target double(b se passthrough pt_se p_full) ///
    using "$TAB/passthrough_ref18.dta", replace

forvalues f = 1/2 {
    local fl = cond(`f' == 1, "petrol", "diesel")
    di _n as text "{hline 78}" _n "FUEL: `fl'" _n "{hline 78}"

    use if fuel == `f' & balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        & inrange(date, $WIN_START, $EST_END) using "$PROC/panel_carburanti_2022.dta", clear
    keep unit_id country italy region date price_c

    * cluster: provincia (IT) / dipartimento (FR); gli impianti senza provincia
    * (non trovati in anagrafica) formano un cluster a parte per paese
    egen long cl_prov = group(country region), missing

    *--------------------------------------------------------------------------
    * A. Verifica dei cluster
    *--------------------------------------------------------------------------
    preserve
        bysort unit_id: keep if _n == 1
        gen byte noreg = missing(region) | region == ""
        forvalues c = 1/2 {
            local cn = cond(`c' == 1, "Italy", "France")
            quietly levelsof cl_prov if country == `c', local(lv)
            quietly count if country == `c'
            local nu = r(N)
            quietly count if country == `c' & noreg
            post `C' ("`fl'") ("`cn'") (`: word count `lv'') (`nu') (r(N))
        }
        di as text "Sigle di provincia italiane nel campione:"
        tab region if country == 1, missing
    restore

    *--------------------------------------------------------------------------
    * B. Event study con riferimento 18 marzo
    *--------------------------------------------------------------------------
    make_days, from($WIN_START) to($EST_END) ref($T0_IT) group(italy) ///
        prefix(ev) omit($T_ANN)
    local evs "`r(vars)'"
    reghdfe price_c `evs', absorb(unit_id date) vce(cluster cl_prov)

    local sum ""
    local n = 0
    foreach v of local evs {
        local k : variable label `v'
        post `E' ("`fl'") (`k') (_b[`v']) (_se[`v'])
        if `k' >= -3 {
            local p = 2 * ttail(e(df_r), abs((_b[`v'] + $CUT_IT) / _se[`v']))
            post `P' ("`fl'") ("day `k'") (_b[`v']) (_se[`v']) ///
                (-_b[`v'] / $CUT_IT) (_se[`v'] / $CUT_IT) (`p')
        }
                if `k' >= 1 {
            if `n' == 0 local sum "`v'"
            else        local sum "`sum' + `v'"
            local ++n
        }
    }
    lincom (`sum') / `n'
    local p = 2 * ttail(e(df_r), abs((r(estimate) + $CUT_IT) / r(se)))
    post `P' ("`fl'") ("avg 23-31 Mar") (r(estimate)) (r(se)) ///
        (-r(estimate) / $CUT_IT) (r(se) / $CUT_IT) (`p')
}
postclose `C'
postclose `E'
postclose `P'

*------------------------------------------------------------------------------
* Riepilogo cluster
*------------------------------------------------------------------------------
use "$TAB/cluster_check.dta", clear
list, sep(2) noobs
export delimited using "$TAB/cluster_check.csv", replace

*------------------------------------------------------------------------------
* Figure
*------------------------------------------------------------------------------
use "$TAB/event_study_ref18.dta", clear
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
foreach fl in petrol diesel {
    local tl = proper("`fl'")
    twoway (rcap hi lo rel_day if fuel == "`fl'", lcolor(navy%60)) ///
           (scatter b rel_day if fuel == "`fl'", mcolor(navy) msize(small)), ///
        yline(0, lcolor(gs10)) yline(-$CUT_IT, lpattern(dash) lcolor(maroon)) ///
        xline(-3.5, lpattern(shortdash) lcolor(gs9)) xline(-0.5, lpattern(dash) lcolor(gs6)) ///
        title("`tl': event study, reference day 18 March") ///
        xtitle("Days since the Italian cut (0 = 22 March, partially treated)") ///
        ytitle("Italy minus France, cents/l") legend(off) ///
        note("Dotted line: announcement (evening of 18 March). Dashed line: entry into force." ///
             "Red line: cut including VAT (-$CUT_IT c/l). 95% CIs. 15-16 March missing.")
    graph export "$FIGEN/fig_es_ref18_`fl'.png", replace width(2000)
}

*------------------------------------------------------------------------------
* Tabella per il paper
*------------------------------------------------------------------------------
use "$TAB/passthrough_ref18.dta", clear
export delimited using "$TAB/passthrough_ref18.csv", replace
gen long ord = _n
bysort fuel (ord): gen row = _n
keep fuel target row b se passthrough pt_se
reshape wide b se passthrough pt_se, i(row target) j(fuel) string
sort row

file open T using "$TAB/tab_es_ref18.tex", write replace
file write T "\begin{tabular}{llcccc}" _n "\toprule" _n
file write T " & & \multicolumn{2}{c}{Petrol} & \multicolumn{2}{c}{Diesel} \\" _n
file write T "\cmidrule(lr){3-4}\cmidrule(lr){5-6}" _n
file write T "Event day & Date & Effect & Pass-through & Effect & Pass-through \\" _n
file write T "\midrule" _n
forvalues r = 1/`=_N' {
    local tg = target[`r']
    if substr("`tg'", 1, 3) == "day" {
        local k = real(word("`tg'", 2))
        local dt : di %tdDD_Mon `=$T0_IT + `k''
        local lab "\(k = `k'\) & `dt'"
    }
    else {
        file write T "\addlinespace" _n
        local lab "Average & 23--31 Mar"
    }
    file write T "`lab'"
    foreach fl in petrol diesel {
        file write T " & " %6.2f (b`fl'[`r']) " (" %4.2f (se`fl'[`r']) ")"
        file write T " & " %5.3f (passthrough`fl'[`r'])
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
list, sep(0) noobs
