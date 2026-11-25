/*==============================================================================
  File   : 11_placebo.do
  Input  : $PROC/panel_carburanti_2022.dta
  Output : $TAB/placebo_dates.dta / .csv     una riga per data placebo e carburante
           $TAB/placebo_summary.dta / .csv   sintesi per finestra e carburante
           $TAB/tab_placebo.tex              tabella per il paper
           $OUT/figures_en/fig_placebo_<fuel>.png

  Perché: il trattamento è assegnato a un solo paese, quindi gli errori standard
  clusterizzati (205 cluster) non misurano l'incertezza sul controfattuale.
  Inferenza placebo nel tempo: si finge che il taglio sia avvenuto in date in
  cui non è successo nulla e si calcola la stessa statistica della stima
  principale. La distribuzione delle statistiche placebo dice quanto si muove
  il gap Italia-Francia in tre giorni "normali"; il confronto con il valore
  vero dice se -28,7 c è eccezionale.

  Statistica (identica al DiD al giorno +2 con riferimento al giorno -1):
      b(t0) = media_IT[p(t0+2) - p(t0-1)] - media_FR[p(t0+2) - p(t0-1)]
  calcolata sui distributori del campione principale (panel bilanciato) con un
  prezzo valido in entrambi i giorni. Per t0 = 22 marzo riproduce la stima
  principale (-28,65 benzina, -35,48 gasolio): è il controllo di coerenza.

  Finestre di date placebo (t0 = primo giorno "trattato" fittizio):
    pre    : 2 gen - 21 feb  (prima dell'invasione; t0+2 <= 23 feb)
    march  : 2 mar - 16 mar  (marzo prima dell'annuncio; t0+2 <= 18 mar)
             finestra più turbolenta, è il confronto più severo
    post   : 12 apr - 28 giu (entrambi i tagli in vigore e invariati)
  Le date con il giorno t0-1 o t0+2 mancanti (15-16 marzo in Italia) sono
  saltate automaticamente.

  Nota: finestre placebo vicine si sovrappongono, quindi le statistiche non
  sono indipendenti. Il p-value è una misura descrittiva (rango del valore vero
  nella distribuzione placebo), non un test esatto.

  Le specificazioni S1-S7 e gli script 01-10 non sono modificati.
==============================================================================*/

global FIGEN "$OUT/figures_en"
capture mkdir "$FIGEN"

local t0_true = $T0_IT

*------------------------------------------------------------------------------
* 0. Dati: campione principale, tutto il semestre
*------------------------------------------------------------------------------
use if balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
    using "$PROC/panel_carburanti_2022.dta", clear
keep unit_id country italy region fuel date price_c

* variazione dal giorno t0-1 al giorno t0+2, indicizzata a t0
tsset unit_id date
gen double d3 = F2.price_c - L1.price_c
drop if missing(d3)
egen long cl = group(country region), missing

gen str6 window = ""
replace window = "pre"   if inrange(date, td(02jan2022), td(21feb2022))
replace window = "march" if inrange(date, td(02mar2022), td(16mar2022))
replace window = "post"  if inrange(date, td(12apr2022), td(28jun2022))
replace window = "true"  if date == `t0_true'
keep if window != ""

tempfile d
save `d'

*------------------------------------------------------------------------------
* 1. Statistica per ogni data e carburante
*------------------------------------------------------------------------------
tempname P
postfile `P' byte fuel long date str6 window double(b se) long(n_it n_fr) ///
    using "$TAB/placebo_dates.dta", replace

levelsof date, local(dates)
forvalues f = 1/2 {
    foreach t of local dates {
        quietly count if fuel == `f' & date == `t' & italy == 1
        local nit = r(N)
        quietly count if fuel == `f' & date == `t' & italy == 0
        local nfr = r(N)
        * servono abbastanza distributori in entrambi i paesi
        if `nit' < 100 | `nfr' < 100 continue
        quietly reg d3 italy if fuel == `f' & date == `t', vce(cluster cl)
        quietly levelsof window if fuel == `f' & date == `t', local(w) clean
        post `P' (`f') (`t') ("`w'") (_b[italy]) (_se[italy]) (`nit') (`nfr')
    }
}
postclose `P'

use "$TAB/placebo_dates.dta", clear
format date %td
label define fuel 1 "Petrol" 2 "Diesel", replace
label values fuel fuel
gen double pt = -b / $CUT_IT
label var b  "Change in IT-FR gap, day -1 to day +2 (cents/l)"
label var pt "Implied pass-through (-b/30.5)"

* controllo di coerenza: la data vera deve riprodurre la stima principale
di as text _n "Data vera (22 marzo):"
list fuel b se pt n_it n_fr if window == "true", noobs

save "$TAB/placebo_dates.dta", replace
export delimited using "$TAB/placebo_dates.csv", replace

*------------------------------------------------------------------------------
* 2. Sintesi per finestra: distribuzione e rango del valore vero
*------------------------------------------------------------------------------
forvalues f = 1/2 {
    quietly summarize b if fuel == `f' & window == "true"
    local btrue`f' = r(mean)
}

tempname S
postfile `S' byte fuel str6 window long n double(mean sd min max maxabs p_abs) ///
    using "$TAB/placebo_summary.dta", replace
forvalues f = 1/2 {
    foreach w in pre march post all {
        if "`w'" == "all" local cond `"inlist(window, "pre", "march", "post")"'
        else              local cond `"window == "`w'""'
        quietly summarize b if fuel == `f' & `cond'
        local n = r(N)
        if `n' == 0 continue
        local mean = r(mean)
        local sd   = r(sd)
        local mn   = r(min)
        local mx   = r(max)
        tempvar ab
        gen double `ab' = abs(b)
        quietly summarize `ab' if fuel == `f' & `cond'
        local maxabs = r(max)
        * quota di placebo con |b| >= |b vero|; il valore vero è incluso nel
        * conteggio (rango), quindi p >= 1/(n+1)
        quietly count if fuel == `f' & `cond' & `ab' >= abs(`btrue`f'')
        local p = (r(N) + 1) / (`n' + 1)
        drop `ab'
        post `S' (`f') ("`w'") (`n') (`mean') (`sd') (`mn') (`mx') (`maxabs') (`p')
    }
}
postclose `S'

use "$TAB/placebo_summary.dta", clear
label values fuel fuel
list, sepby(fuel) noobs
export delimited using "$TAB/placebo_summary.csv", replace

*------------------------------------------------------------------------------
* 3. Figura: statistica per ogni data, con la data vera evidenziata
*------------------------------------------------------------------------------
use "$TAB/placebo_dates.dta", clear
forvalues f = 1/2 {
    local fl = cond(`f' == 1, "petrol", "diesel")
    local tl = cond(`f' == 1, "Petrol", "Diesel")
    * barra verticale da 0 a b per ogni data
    gen double zero = 0
    twoway ///
        (rspike zero b date if fuel == `f' & window == "pre",   lcolor(gs8)   lwidth(medthick)) ///
        (rspike zero b date if fuel == `f' & window == "march", lcolor(orange) lwidth(medthick)) ///
        (rspike zero b date if fuel == `f' & window == "post",  lcolor(gs8)   lwidth(medthick)) ///
        (rspike zero b date if fuel == `f' & window == "true",  lcolor(maroon) lwidth(vthick)), ///
        yline(0, lcolor(gs12)) yline(-$CUT_IT, lpattern(dash) lcolor(gs6)) ///
        title("`tl': change in the Italy-France gap over three days") ///
        ytitle("Cents per litre") xtitle("Placebo date of the cut") ///
        xlabel(`=td(01jan2022)' `=td(01feb2022)' `=td(01mar2022)' `=td(01apr2022)' ///
               `=td(01may2022)' `=td(01jun2022)' `=td(01jul2022)', format(%tdMon)) ///
        legend(order(1 "Placebo dates" 2 "Placebo dates, March before the announcement" ///
                     4 "Actual cut, 22 March") rows(1) size(small)) ///
        note("Each bar: change in the average Italy-France price gap from the day before to two days after" ///
             "the date. Dashed line: full pass-through of the cut (-30.5 cents).")
    graph export "$FIGEN/fig_placebo_`fl'.png", replace width(2000)
    drop zero
}

*------------------------------------------------------------------------------
* 4. Tabella LaTeX
*------------------------------------------------------------------------------
use "$TAB/placebo_summary.dta", clear
tempname T
file open `T' using "$TAB/tab_placebo.tex", write replace
file write `T' "\begin{tabular}{llcccccc}" _n "\toprule" _n
file write `T' " & Placebo dates & \textit{N} & Mean & SD & Min & Max & \textit{p} \\" _n "\midrule" _n
forvalues f = 1/2 {
    local tl = cond(`f' == 1, "Petrol", "Diesel")
    file write `T' "\multicolumn{8}{l}{\textit{`tl': actual change = " %5.1f (`btrue`f'') " cents}} \\" _n
    foreach w in pre march post all {
        if "`w'" == "pre"   local wl "2 Jan -- 21 Feb (pre-invasion)"
        if "`w'" == "march" local wl "2 -- 16 Mar (before announcement)"
        if "`w'" == "post"  local wl "12 Apr -- 28 Jun (both cuts in force)"
        if "`w'" == "all"   local wl "All placebo dates"
        quietly count if fuel == `f' & window == "`w'"
        if r(N) == 0 continue
        quietly summarize n if fuel == `f' & window == "`w'"
        local n = r(mean)
        foreach v in mean sd min max p_abs {
            quietly summarize `v' if fuel == `f' & window == "`w'"
            local `v' = r(mean)
        }
        if "`w'" == "all" file write `T' "\addlinespace" _n
        file write `T' " & `wl' & " %3.0f (`n') " & " %5.1f (`mean') " & " %4.1f (`sd') ///
            " & " %5.1f (`min') " & " %5.1f (`max') " & " %5.3f (`p_abs') " \\" _n
    }
    if `f' == 1 file write `T' "\addlinespace" _n
}
file write `T' "\bottomrule" _n "\end{tabular}" _n
file close `T'

di as text _n "11_placebo completato: $TAB/tab_placebo.tex"
