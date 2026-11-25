/*==============================================================================
  File   : 08_paper_outputs.do
  Input  : $PROC/panel_carburanti_2022.dta
           $TAB/event_study_coef.dta, $TAB/event_study_rif21.dta,
           $TAB/risultati_passthrough.dta          (prodotti da 06 e 07)
  Output : $OUT/figures_en/*.png     tutte le figure del paper, in inglese
           $TAB/tab_descriptive.tex   statistiche descrittive (pre-taglio)
           $TAB/tab_results.tex       stime di pass-through S1-S7
  Note   : le figure sono ricostruite dai risultati salvati; solo le regressioni
           di honestdid vengono rilanciate (finestra 17-31 marzo, veloci).
           Va lanciato dopo 06 e 07.
==============================================================================*/
*/

global FIGEN "$OUT/figures_en"
capture mkdir "$FIGEN"
set scheme s1color

* le etichette vanno ridefinite dopo ogni -use-, che le sostituisce
local labs `"label define country_en 1 "Italy" 2 "France", replace"'
local labf `"label define fuel_en 1 "Petrol" 2 "Diesel", replace"'
local en1 "Petrol"
local en2 "Diesel"
local fname1 "petrol"
local fname2 "diesel"

local xl "xline($T0_IT, lpattern(dash) lcolor(gs5)) xline($T0_FR, lpattern(shortdash) lcolor(gs11))"
local xlab_full `"xlabel(`=td(01jan2022)'(14)`=td(30jun2022)', format(%tdDD_Mon) angle(45))"'
local xlab_zoom `"xlabel(`=td(01mar2022)'(5)`=td(15apr2022)', format(%tdDD_Mon) angle(45))"'
local note_ev "Dashed line: Italian excise cut (22 Mar). Dotted line: French fuel rebate (1 Apr)."

*==============================================================================
* A. Statistiche descrittive e figure descrittive
*==============================================================================
use "$PROC/panel_carburanti_2022.dta", clear
`labs'
`labf'
keep if highway != 1 & !stale & !missing(price_c) & balanced == 1
label values country country_en
label values fuel fuel_en

*------------------------------------------------------------------------------
* Tabella descrittiva: 1-21 marzo 2022
*------------------------------------------------------------------------------
preserve
    keep if inrange(date, $WIN_START, $T0_IT - 1)
    egen byte tag = tag(country fuel station_id)
    collapse (mean) p = price_c (sd) sdp = price_c (mean) dsu = days_since_update ///
        chg = changed (sum) nst = tag, by(country fuel)
    sort country fuel
    file open T using "$TAB/tab_descriptive.tex", write replace
    file write T "\begin{tabular}{llrrrrr}" _n "\toprule" _n
    file write T "Country & Fuel & Stations & Mean price & SD & Days since & Share changing \\" _n
    file write T " & & & (cents/l) & (cents/l) & last update & price per day \\" _n
    file write T "\midrule" _n
    forvalues i = 1/`=_N' {
        local c  : label country_en `=country[`i']'
        local fu : label fuel_en `=fuel[`i']'
        file write T "`c' & `fu' & " %9.0fc (nst[`i']) " & " %6.1f (p[`i']) ///
            " & " %5.1f (sdp[`i']) " & " %5.1f (dsu[`i']) " & " %5.2f (chg[`i']) " \\" _n
    }
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T
restore

*------------------------------------------------------------------------------
* Prezzi medi, quota di impianti che cambiano prezzo, numero di impianti, divario
*------------------------------------------------------------------------------
preserve
    collapse (mean) price_c changed (count) n = price_c, by(country fuel date)

    forvalues f = 1/2 {
        local fl : label fuel_en `f'
        twoway (line price_c date if country == 1 & fuel == `f', lcolor(navy)) ///
               (line price_c date if country == 2 & fuel == `f', lcolor(maroon)), ///
            `xl' `xlab_full' title("`fl': average pump price") ///
            ytitle("Euro cents per litre") xtitle("") ///
            legend(order(1 "Italy" 2 "France") rows(1) pos(6)) note("`note_ev'")
        graph export "$FIGEN/fig_prices_`fname`f''.png", replace width(2000)

        twoway (connected changed date if country == 1 & fuel == `f', ///
                    lcolor(navy) mcolor(navy) msize(small)) ///
               (connected changed date if country == 2 & fuel == `f', ///
                    lcolor(maroon) mcolor(maroon) msize(small)) ///
               if inrange(date, td(01mar2022), td(15apr2022)), ///
            `xl' `xlab_zoom' title("`fl': share of stations changing their price") ///
            ytitle("Share of stations") xtitle("") ///
            legend(order(1 "Italy" 2 "France") rows(1) pos(6)) note("`note_ev'")
        graph export "$FIGEN/fig_share_changing_`fname`f''.png", replace width(2000)
    }

    twoway (line n date if country == 1 & fuel == 1, lcolor(navy)) ///
           (line n date if country == 2 & fuel == 1, lcolor(maroon)), ///
        `xl' `xlab_full' title("Stations observed per day (petrol)") ///
        ytitle("Number of stations") xtitle("") ///
        legend(order(1 "Italy" 2 "France") rows(1) pos(6))
    graph export "$FIGEN/fig_n_stations.png", replace width(2000)

    keep country fuel date price_c
    reshape wide price_c, i(fuel date) j(country)
    gen diff = price_c1 - price_c2

    twoway (line diff date if fuel == 1, lcolor(navy)) ///
           (line diff date if fuel == 2, lcolor(dkorange)), ///
        `xl' `xlab_full' title("Price gap, Italy minus France") ///
        subtitle("Italian cut = $CUT_IT c/l (22 Mar); French rebate = $CUT_FR c/l (1 Apr)") ///
        ytitle("Euro cents per litre") xtitle("") ///
        legend(order(1 "Petrol" 2 "Diesel") rows(1) pos(6))
    graph export "$FIGEN/fig_gap_full.png", replace width(2000)

    twoway (connected diff date if fuel == 1, lcolor(navy) mcolor(navy) msize(small)) ///
           (connected diff date if fuel == 2, lcolor(dkorange) mcolor(dkorange) msize(small)) ///
           if inrange(date, td(01mar2022), td(15apr2022)), ///
        `xl' `xlab_zoom' title("Price gap, Italy minus France, 1 March - 15 April") ///
        ytitle("Euro cents per litre") xtitle("") ///
        legend(order(1 "Petrol" 2 "Diesel") rows(1) pos(6)) note("`note_ev'")
    graph export "$FIGEN/fig_gap_zoom.png", replace width(2000)
restore

*------------------------------------------------------------------------------
* Variazione di prezzo per impianto, 21 marzo - 25 marzo
*------------------------------------------------------------------------------
gen dp = price_c - L4.price_c if date == $T0_IT + 3
forvalues f = 1/2 {
    local fl : label fuel_en `f'
    twoway (kdensity dp if italy == 1 & fuel == `f', lcolor(navy)) ///
           (kdensity dp if italy == 0 & fuel == `f', lcolor(maroon)), ///
        xline(-$CUT_IT, lpattern(dash) lcolor(gs5)) ///
        title("`fl': station-level price change, 21-25 March") ///
        xtitle("Euro cents per litre") ytitle("Density") ///
        note("Dashed line: Italian cut including VAT (-$CUT_IT c/l).") ///
        legend(order(1 "Italy" 2 "France") rows(1) pos(6))
    graph export "$FIGEN/fig_station_change_`fname`f''.png", replace width(2000)
}

*------------------------------------------------------------------------------
* Giorni dall'ultimo aggiornamento (campione completo)
*------------------------------------------------------------------------------
use "$PROC/panel_carburanti_2022.dta", clear
`labs'
label values country country_en
histogram days_since_update if date == $T0_IT - 1 & highway != 1 & ///
    inrange(days_since_update, 0, 60), discrete percent ///
    by(country, title("Days since last price update, 21 March 2022") note("")) ///
    xtitle("Days") ytitle("Percent")
graph export "$FIGEN/fig_days_since_update.png", replace width(2000)

*==============================================================================
* B. Event study (dai coefficienti salvati)
*==============================================================================
local en_benzina "Petrol"
local en_gasolio "Diesel"
local fn_benzina "petrol"
local fn_gasolio "diesel"
local xt_it "Days since the Italian cut (0 = 22 March, partially treated)"
local yt_it "Italy minus France, cents/l"
local nt_it "Dashed red line: cut including VAT (-$CUT_IT c/l). 95% confidence intervals."

*------------------------------------------------------------------------------
* Specificazione principale: riferimento 21 marzo
*------------------------------------------------------------------------------
use "$TAB/event_study_rif21.dta", clear
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
foreach fl in benzina gasolio {
    twoway (rcap hi lo rel_day if fuel == "`fl'", lcolor(navy%60)) ///
           (scatter b rel_day if fuel == "`fl'", mcolor(navy) msize(small)), ///
        yline(0, lcolor(gs10)) yline(-$CUT_IT, lpattern(dash) lcolor(maroon)) ///
        xline(-0.5, lpattern(dash) lcolor(gs6)) ///
        title("`en_`fl'': event study, reference day 21 March") ///
        xtitle("`xt_it'") ytitle("`yt_it'") legend(off) ///
        note("`nt_it' 15-16 March missing in the MIMIT archive.")
    graph export "$FIGEN/fig_es_ref21_`fn_`fl''.png", replace width(2000)
}

*------------------------------------------------------------------------------
* Specificazioni alternative (appendice)
*------------------------------------------------------------------------------
use "$TAB/event_study_coef.dta", clear
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se

local t_S2  "No cost controls (reference: average Jan-Feb gap)"
local t_S3  "Brent controls, lags estimated on Jan-Feb"
local t_S3p "Product-price controls (NY Harbor), lags estimated on Jan-Feb"
local t_S4  "Imputation, Brent controls estimated on 1 Jan - 21 Mar"
local t_S4p "Imputation, product-price controls estimated on 1 Jan - 21 Mar"
local t_S5  "Imputation, linear Italian trend estimated on 1-21 Mar"

foreach s in S2 S3 S3p S4 S4p S5 {
    foreach fl in benzina gasolio {
        quietly count if spec == "`s'" & fuel == "`fl'"
        if r(N) == 0 continue
        twoway (rcap hi lo rel_day if spec == "`s'" & fuel == "`fl'", lcolor(navy%60)) ///
               (scatter b rel_day if spec == "`s'" & fuel == "`fl'", mcolor(navy) msize(small)), ///
            yline(0, lcolor(gs10)) yline(-$CUT_IT, lpattern(dash) lcolor(maroon)) ///
            xline(-0.5, lpattern(dash) lcolor(gs6)) ///
            title("`en_`fl'': event study `s'") subtitle("`t_`s''") ///
            xtitle("`xt_it'") ytitle("`yt_it'") legend(off) note("`nt_it'")
        graph export "$FIGEN/fig_es_`s'_`fn_`fl''.png", replace width(2000)
    }
}

foreach fl in benzina gasolio {
    twoway (rcap hi lo rel_day if spec == "S7" & fuel == "`fl'", lcolor(maroon%60)) ///
           (scatter b rel_day if spec == "S7" & fuel == "`fl'", mcolor(maroon) msize(small)), ///
        yline(0, lcolor(gs10)) yline(-$CUT_FR, lpattern(dash) lcolor(navy)) ///
        xline(-0.5, lpattern(dash) lcolor(gs6)) ///
        title("`en_`fl'': French fuel rebate, Italy as control") ///
        xtitle("Days since the French rebate (0 = 1 April, partially treated; ref. = 31 March)") ///
        ytitle("France minus Italy, cents/l") legend(off) ///
        note("Dashed blue line: rebate including VAT (-$CUT_FR c/l). 95% confidence intervals.")
    graph export "$FIGEN/fig_es_S7_`fn_`fl''.png", replace width(2000)
}

*==============================================================================
* C. Tabella dei risultati S1-S7
*==============================================================================
use "$TAB/risultati_passthrough.dta", clear
gen code = word(spec, 1)
keep code fuel b se passthrough pt_se p_full
reshape wide b se passthrough pt_se p_full, i(code) j(fuel) string
gen ord = .
local i = 0
foreach c in S1 S2 S3 S3p S4 S4p S5 S6 S7 {
    local ++i
    quietly replace ord = `i' if code == "`c'"
}
drop if missing(ord)
sort ord

local d_S1  "(S1) Static DiD, March"
local d_S2  "(S2) Event study vs.\ Jan--Feb, no controls"
local d_S3  "(S3) As S2, Brent lags (Jan--Feb)"
local d_S3p "(S3p) As S2, product-price lags (Jan--Feb)"
local d_S4  "(S4) Imputation, Brent lags (1 Jan--21 Mar)"
local d_S4p "(S4p) Imputation, product-price lags"
local d_S5  "(S5) Imputation, linear Italian trend"
local d_S6  "(S6) Quiet periods, continuous tax cut"
local d_S7  "(S7) French rebate, Italy as control"

file open T using "$TAB/tab_results.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Petrol} & \multicolumn{3}{c}{Diesel} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Specification & Effect & Pass-through & \(p\) (PT = 1) & Effect & Pass-through & \(p\) (PT = 1) \\" _n
file write T "\midrule" _n
forvalues r = 1/`=_N' {
    local c = code[`r']
    file write T "`d_`c''"
    foreach fl in benzina gasolio {
        if "`c'" == "S6" {
            file write T " & --"
        }
        else {
            file write T " & " %6.2f (b`fl'[`r']) " (" %4.2f (se`fl'[`r']) ")"
        }
        file write T " & " %5.3f (passthrough`fl'[`r']) " (" %5.3f (pt_se`fl'[`r']) ")"
        file write T " & " %5.3f (p_full`fl'[`r'])
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

*==============================================================================
* D. honestdid in inglese (rilancia solo le regressioni 17-31 marzo)
*==============================================================================
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

global HD_START = td(17mar2022)
global HD_REF   = $T0_IT - 1

forvalues f = 1/2 {
    local fl "`en`f''"
    use if fuel == `f' & balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        & inrange(date, $HD_START, $EST_END) using "$PROC/panel_carburanti_2022.dta", clear
    egen long cl = group(country region), missing
    make_days, from($HD_START) to($EST_END) ref($T0_IT) group(italy) ///
        prefix(ev) omit($HD_REF)
    local evs "`r(vars)'"
    local npre  = 0
    local npost = 0
    foreach v of local evs {
        local k : variable label `v'
        if `k' < 0 local ++npre
        else       local ++npost
    }
    local pre  "1/`npre'"
    local post "`=`npre' + 1'/`=`npre' + `npost''"
    quietly reghdfe price_c `evs', absorb(unit_id date) vce(cluster cl)

    matrix L_g2 = J(`npost', 1, 0)
    matrix L_g2[3, 1] = 1
    matrix L_avg = J(`npost', 1, 1 / (`npost' - 1))
    matrix L_avg[1, 1] = 0
    local tit_g2  "day +2 (24 March)"
    local tit_avg "average of days +1 to +9"

    foreach tg in g2 avg {
        honestdid, pre(`pre') post(`post') l_vec(L_`tg') mvec(0(0.25)1.5) ///
            delta(rm) coefplot xtitle("Mbar") ytitle("95% robust CI, cents/l") ///
            title("`fl': `tit_`tg'', relative magnitudes")
        graph export "$FIGEN/fig_hd_rm_`tg'_`fname`f''.png", replace width(2000)

        honestdid, pre(`pre') post(`post') l_vec(L_`tg') mvec(0(0.25)1) ///
            delta(sd) coefplot xtitle("M") ytitle("95% robust CI, cents/l") ///
            title("`fl': `tit_`tg'', smoothness")
        graph export "$FIGEN/fig_hd_sd_`tg'_`fname`f''.png", replace width(2000)
    }
}
