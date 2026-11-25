/*==============================================================================
  File   : 03_build_panel.do
  Input  : $TEMP/italy_clean.dta, $TEMP/france_clean.dta
  Output : $PROC/panel_carburanti_2022.dta   (gen-giu 2022, tutte le variabili)
           $PROC/panel_finestra.dta          (solo la finestra di stima)
  Unità  : impianto x carburante x giorno (unit_id x date), xtset
==============================================================================*/

use "$TEMP/italy_clean.dta", clear
append using "$TEMP/france_clean.dta"

*------------------------------------------------------------------------------
* Codifiche
*------------------------------------------------------------------------------
label define country 1 "Italia" 2 "Francia"
label values country country
gen byte italy = country == 1

gen byte fuel_n = 1 if fuel == "benzina"
replace  fuel_n = 2 if fuel == "gasolio"
label define fuel 1 "Benzina" 2 "Gasolio"
label values fuel_n fuel
drop fuel
rename fuel_n fuel

egen long station_id = group(country station_orig)
egen long unit_id    = group(country station_orig fuel)
isid unit_id date
xtset unit_id date, daily

*------------------------------------------------------------------------------
* Pulizia del prezzo
*------------------------------------------------------------------------------
gen byte outlier = !inrange(price, $PMIN, $PMAX) & !missing(price)
replace price = . if outlier
gen double price_c = price * 100

gen int  days_since_update = date - date_update
gen byte stale = days_since_update > $STALE_MAX & !missing(days_since_update)

* variazioni giornaliere (utili per la velocità di aggiustamento)
gen double d_price_c = D.price_c
gen byte   changed   = d_price_c != 0 if !missing(d_price_c)

*------------------------------------------------------------------------------
* Trattamento
*------------------------------------------------------------------------------
gen int  rel_day    = date - $T0_IT          // giorni dal taglio italiano
gen byte post       = date >= $T0_IT
gen byte treat_post = italy * post

* intensità del taglio fiscale in centesimi/litro IVA inclusa.
* ATTENZIONE: verificare che il taglio italiano resti 30,5 c per entrambi i
* carburanti fino a giugno e che la remise francese resti 18 c (fino al 31/8).
gen double tax_cut_c = 0
replace tax_cut_c = $CUT_IT if italy == 1 & date >= $T0_IT
replace tax_cut_c = $CUT_FR if italy == 0 & date >= $T0_FR

*------------------------------------------------------------------------------
* Geografia: province e dipartimenti al confine italo-francese
*------------------------------------------------------------------------------
gen byte border = (italy == 1 & inlist(region, "IM", "CN", "TO", "AO")) | ///
                  (italy == 0 & inlist(region, "06", "04", "05", "73", "74"))

*------------------------------------------------------------------------------
* Campioni
*------------------------------------------------------------------------------
gen byte in_window   = inrange(date, $WIN_START, $WIN_END)
gen byte sample_main = in_window & !missing(price_c) & !stale & highway != 1

* panel bilanciato: osservazione valida in tutti i giorni della finestra in cui
* il paese ha dati. Nell'archivio MIMIT mancano alcuni giorni (es. 15-16 marzo
* 2022): richiedere tutti i giorni del calendario escluderebbe tutta l'Italia.
bysort country date: gen byte _dday = (_n == 1) & in_window
bysort country: egen n_days_country = total(_dday)
drop _dday
bysort unit_id: egen n_ok = total(sample_main)
gen byte balanced = n_ok == n_days_country
drop n_ok

di _n "Giorni con dati nella finestra, per paese:"
tabstat n_days_country, by(country) stat(mean)
drop n_days_country
xtset unit_id date, daily

*------------------------------------------------------------------------------
* Etichette e salvataggio
*------------------------------------------------------------------------------
label var country           "Paese"
label var italy             "1 = Italia (trattato)"
label var station_orig      "Id originale impianto (MIMIT / prix-carburants)"
label var station_id        "Id impianto"
label var unit_id           "Id impianto x carburante"
label var fuel              "Carburante"
label var date              "Giorno (prezzo in vigore alle 8:00)"
label var price             "Prezzo alla pompa, euro/l"
label var price_c           "Prezzo alla pompa, centesimi/l"
label var date_update       "Data dell'ultima variazione di prezzo comunicata"
label var days_since_update "Giorni dall'ultima variazione"
label var stale             "Prezzo non aggiornato da > $STALE_MAX giorni"
label var outlier           "Prezzo fuori da [$PMIN, $PMAX], posto a missing"
label var d_price_c         "Variazione giornaliera del prezzo, centesimi"
label var changed           "1 = prezzo cambiato rispetto al giorno prima"
label var rel_day           "Giorni dal taglio italiano (0 = 22/3/2022)"
label var post              "Dal 22/3/2022"
label var treat_post        "Italia x post"
label var tax_cut_c         "Taglio fiscale in vigore, centesimi/l IVA inclusa"
label var region            "Provincia (IT) / dipartimento (FR)"
label var highway           "Impianto autostradale"
label var border            "Provincia/dipartimento di confine IT-FR"
label var in_window         "Nella finestra principale di stima"
label var sample_main       "Campione principale (finestra, no autostrada, no stale)"
label var balanced          "Osservato in tutti i giorni della finestra"
label var in_anagrafica     "Impianto trovato in anagrafica"

order country italy station_id unit_id station_orig fuel date price price_c ///
      rel_day post treat_post tax_cut_c
compress
save "$PROC/panel_carburanti_2022.dta", replace

* riepilogo
di _n "Unità impianto-carburante nel campione bilanciato:"
tab country fuel if balanced == 1 & date == $WIN_START
di _n "Prezzo medio pre-taglio nella finestra (centesimi):"
tabstat price_c if sample_main & balanced & date < $T0_IT, by(country) stat(mean sd n)

preserve
    keep if in_window
    save "$PROC/panel_finestra.dta", replace
restore
