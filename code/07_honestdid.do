/*==============================================================================
  File   : 07_honestdid.do
  Input  : $PROC/panel_carburanti_2022.dta
  Output : $TAB/event_study_rif21.dta     coefficienti dell'event study (rif. 21/3)
           $FIG/es_rif21_<carburante>.png  event study su marzo, rif. 21/3
           $FIG/hd_<restrizione>_<bersaglio>_<carburante>.png  intervalli robusti
           (le tabelle di honestdid sono nel log)

  Idea (Rambachan e Roth, 2023): invece di assumere trend paralleli esatti, si
  calcolano intervalli di confidenza validi se, dopo il taglio, la deviazione dai
  trend paralleli non è "troppo diversa" da quella osservata prima.

  Due restrizioni:
    - delta(rm), relative magnitudes: la variazione giornaliera della deviazione
      dopo il taglio non supera Mbar volte la massima variazione giornaliera
      osservata prima. Mbar = 0 equivale ai trend paralleli rispetto al 21/3.
    - delta(sd), smoothness: la deviazione prosegue il trend lineare pre-taglio,
      con una curvatura che può cambiare al massimo di M centesimi al giorno.
      M = 0 equivale a estrapolare in linea retta il trend dell'ultima settimana.

  Finestra: 17-31 marzo. Pre = 17-20 marzo (giorni -5..-2), riferimento = 21/3
  (giorno -1), post = 22-31 marzo (giorni 0..9). La finestra parte dal 17
  perché il 15 e il 16 mancano nell'archivio MIMIT: honestdid tratta i
  coefficienti come giorni consecutivi.

  Due bersagli:
    - g2:  effetto al giorno +2 (24/3), il primo giorno ad aggiustamento quasi completo
    - avg: media dei giorni +1..+9 (23-31 marzo)
  Le stime sono in centesimi/l: pass-through = -(stima) / 30,5.
  Con relative magnitudes la distorsione ammessa si accumula giorno per giorno,
  quindi il bersaglio g2 è molto più informativo della media su 9 giorni.
==============================================================================*/

*------------------------------------------------------------------------------
* Pacchetti
*------------------------------------------------------------------------------
foreach p in ftools reghdfe coefplot honestdid {
    capture which `p'
    if _rc ssc install `p', replace
}
honestdid _plugin_check

*------------------------------------------------------------------------------
* Date
*------------------------------------------------------------------------------
global HD_START = td(17mar2022)
global HD_REF   = $T0_IT - 1          // 21 marzo

*------------------------------------------------------------------------------
* Programma: dummy gruppo x giorno (come in 06, ridefinito per poter lanciare
* questo file da solo)
*------------------------------------------------------------------------------
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

*------------------------------------------------------------------------------
* Stime
*------------------------------------------------------------------------------
tempname E
postfile `E' str8 fuel int rel_day double(b se) ///
    using "$TAB/event_study_rif21.dta", replace

forvalues f = 1/2 {
    local fl = cond(`f' == 1, "benzina", "gasolio")
    di _n as text "{hline 78}" _n "CARBURANTE: `fl'" _n "{hline 78}"

    use if fuel == `f' & balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
        using "$PROC/panel_carburanti_2022.dta", clear
    keep unit_id country italy region date price_c
    egen long cl = group(country region), missing

    *--------------------------------------------------------------------------
    * A. Event study su tutto marzo con riferimento 21/3 (per il grafico)
    *--------------------------------------------------------------------------
    preserve
        keep if inrange(date, $WIN_START, $EST_END)
        make_days, from($WIN_START) to($EST_END) ref($T0_IT) group(italy) ///
            prefix(ev) omit($HD_REF)
        local evs "`r(vars)'"
        reghdfe price_c `evs', absorb(unit_id date) vce(cluster cl)
        foreach v of local evs {
            local k : variable label `v'
            post `E' ("`fl'") (`k') (_b[`v']) (_se[`v'])
        }
    restore

    *--------------------------------------------------------------------------
    * B. honestdid su 17-31 marzo
    *--------------------------------------------------------------------------
    keep if inrange(date, $HD_START, $EST_END)
    make_days, from($HD_START) to($EST_END) ref($T0_IT) group(italy) ///
        prefix(ev) omit($HD_REF)
    local evs "`r(vars)'"

    * conta coefficienti pre e post (l'ordine in e(b) è quello di `evs')
    local npre  = 0
    local npost = 0
    foreach v of local evs {
        local k : variable label `v'
        if `k' < 0 local ++npre
        else       local ++npost
    }
    local pre  "1/`npre'"
    local post "`=`npre' + 1'/`=`npre' + `npost''"
    di as text "Coefficienti pre: `npre' (indici `pre'); post: `npost' (indici `post')"

    reghdfe price_c `evs', absorb(unit_id date) vce(cluster cl)

    * bersagli (vettori lunghi quanto i coefficienti post, che partono dal giorno 0)
    matrix L_g2 = J(`npost', 1, 0)
    matrix L_g2[3, 1] = 1                         // giorno +2
    matrix L_avg = J(`npost', 1, 1 / (`npost' - 1))
    matrix L_avg[1, 1] = 0                        // escluso il giorno 0
    local tit_g2  "giorno +2 (24/3)"
    local tit_avg "media giorni +1..+9"

    foreach tg in g2 avg {
        di _n as result "honestdid - `fl' - bersaglio: `tit_`tg'' - relative magnitudes"
        honestdid, pre(`pre') post(`post') l_vec(L_`tg') mvec(0(0.25)1.5) ///
            delta(rm) coefplot xtitle("Mbar") ///
            ytitle("IC robusto al 95%, centesimi/l") ///
            title("`fl': `tit_`tg'', relative magnitudes")
        graph export "$FIG/hd_rm_`tg'_`fl'.png", replace width(2000)

        di _n as result "honestdid - `fl' - bersaglio: `tit_`tg'' - smoothness"
        honestdid, pre(`pre') post(`post') l_vec(L_`tg') mvec(0(0.25)1) ///
            delta(sd) coefplot xtitle("M") ///
            ytitle("IC robusto al 95%, centesimi/l") ///
            title("`fl': `tit_`tg'', smoothness")
        graph export "$FIG/hd_sd_`tg'_`fl'.png", replace width(2000)
    }
    di as text "Pass-through = -(estremi dell'intervallo) / $CUT_IT"
}

postclose `E'

*------------------------------------------------------------------------------
* Grafico dell'event study con riferimento 21/3
*------------------------------------------------------------------------------
use "$TAB/event_study_rif21.dta", clear
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
foreach fl in benzina gasolio {
    twoway (rcap hi lo rel_day if fuel == "`fl'", lcolor(navy%60)) ///
           (scatter b rel_day if fuel == "`fl'", mcolor(navy) msize(small)), ///
        yline(0, lcolor(gs10)) yline(-$CUT_IT, lpattern(dash) lcolor(maroon)) ///
        xline(-0.5, lpattern(dash) lcolor(gs6)) ///
        title("`fl': event study, riferimento 21 marzo") ///
        xtitle("giorni dal taglio (0 = 22/3, solo in parte trattato)") ///
        ytitle("Italia - Francia, centesimi/l") legend(off) ///
        note("Linea rossa: taglio con IVA (-$CUT_IT c/l). Intervalli al 95%. 15-16/3 mancanti.")
    graph export "$FIG/es_rif21_`fl'.png", replace width(2000)
}
