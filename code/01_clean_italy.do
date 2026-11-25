/*==============================================================================
  File   : 01_clean_italy.do
  Input  : $RAW/2022_1_tr_price, $RAW/2022_2_tr_price
             prezzo_alle_8-AAAAMMGG.csv   (fotografia dei prezzi alle 8:00)
           $RAW/2022_1_tr-an, $RAW/2022_2_tr-an
             anagrafica_impianti_attivi-AAAAMMGG.csv
  Output : $TEMP/italy_clean.dta   (impianto x carburante x giorno)
  Note   : il prezzo del giorno d è l'ultimo prezzo comunicato prima delle 8:00
           di d. dtComu è la data dell'ultima comunicazione: serve per
           individuare i prezzi non aggiornati.
==============================================================================*/

*------------------------------------------------------------------------------
* Programma: importa un csv MIMIT e usa la riga di intestazione come nomi.
* I file iniziano con una riga "Estrazione del ..." e poi l'intestazione;
* il programma cerca la riga che contiene "idImpianto", quindi funziona
* anche se la riga iniziale manca. Accetta sia ";" sia "|" come separatore.
*------------------------------------------------------------------------------
*
* Opzione right(#): nell'anagrafica alcuni indirizzi contengono l'entità HTML
* "&#039;" (apostrofo), il cui ";" spezza la riga in 11-12 colonne invece di 10.
* Le ultime colonne (Comune, Provincia, Latitudine, Longitudine) restano però
* corrette se lette da destra: right(4) le riallinea alla posizione giusta.
*------------------------------------------------------------------------------
capture program drop mimit_read
program define mimit_read
    syntax using/ [, right(integer 0)]
    quietly {
        import delimited using "`using'", varnames(nonames) stringcols(_all) ///
            delimiters(";|") bindquote(nobind) encoding("utf-8") clear
        gen long _row = _n
        summarize _row if strpos(lower(v1), "idimpianto") > 0, meanonly
        if r(N) == 0 {
            noisily di as error "Intestazione 'idImpianto' non trovata in `using'"
            exit 459
        }
        local hdr = r(min)

        * numero di colonne dell'intestazione (H) e del file (K)
        unab allv : v*
        local K : word count `allv'
        local H = 0
        forvalues j = 1/`K' {
            if strtrim(v`j'[`hdr']) != "" local H = `j'
        }

        * riallineamento da destra delle righe con colonne in più
        if `right' > 0 & `K' > `H' {
            gen int _ncol = 0
            forvalues j = 1/`K' {
                replace _ncol = `j' if strtrim(v`j') != ""
            }
            gen int _shift = _ncol - `H'
            count if _shift > 0
            noisily di as text "  `using': `r(N)' righe riallineate"
            forvalues s = 1/`=`K' - `H'' {
                forvalues j = `=`H' - `right' + 1'/`H' {
                    replace v`j' = v`=`j' + `s'' if _shift == `s'
                }
            }
            drop _ncol _shift
        }

        * "NULL" usato dal MIMIT per i valori mancanti
        foreach v of varlist v* {
            replace `v' = "" if strtrim(`v') == "NULL" & _row > `hdr'
        }

        foreach v of varlist v* {
            local nm = strtoname(ustrregexra(lower(strtrim(`v'[`hdr'])), "[^a-z0-9 ]", ""))
            if inlist("`nm'", "", "_") {
                drop `v'        // colonne senza intestazione (righe malformate)
            }
            else {
                capture rename `v' `nm'
            }
        }
        drop if _row <= `hdr'
        drop _row
    }
end

*==============================================================================
* A. PREZZI: un file al giorno -> filtro -> salvo in temp
*==============================================================================
local n_files = 0
foreach q in 2022_1_tr_price 2022_2_tr_price {
    local files : dir "$RAW/`q'" files "prezzo_alle_8-*.csv"
    foreach f of local files {
        local ds = ustrregexra("`f'", "^.*-|\.csv$", "")      // AAAAMMGG
        local d  = date("`ds'", "YMD")
        if missing(`d') | `d' < $PANEL_START | `d' > $PANEL_END continue

        mimit_read using "$RAW/`q'/`f'"
        keep idimpianto desccarburante prezzo isself dtcomu

        * carburanti: solo benzina e gasolio "standard"
        * (esclusi Blue Super, HiQ, Gasolio Premium ecc.)
        gen fuel = ""
        replace fuel = "benzina" if lower(strtrim(desccarburante)) == "benzina"
        replace fuel = "gasolio" if lower(strtrim(desccarburante)) == "gasolio"
        keep if fuel != ""

        replace prezzo = subinstr(strtrim(prezzo), ",", ".", .)
        destring idimpianto isself prezzo, replace force
        drop if missing(idimpianto)
        if $IT_SELF == 1 keep if isself == 1

        * data dell'ultima comunicazione del prezzo
        gen double tc_comu = clock(dtcomu, "DMYhms")
        replace tc_comu = clock(dtcomu, "YMDhms") if missing(tc_comu)
        gen date_comu = dofc(tc_comu)
        gen date = `d'

        * eventuali duplicati impianto-carburante nello stesso giorno:
        * media del prezzo, comunicazione più recente, numero di record
        collapse (mean) price = prezzo (max) date_comu (count) n_rec = prezzo, ///
            by(idimpianto fuel date)

        save "$TEMP/it_prezzi/p_`ds'.dta", replace
        local ++n_files
    }
}
di as text "File prezzi MIMIT letti: `n_files'"
if `n_files' == 0 {
    di as error "Nessun file prezzi letto: controlla nomi e percorsi."
    exit 601
}

clear
local pfiles : dir "$TEMP/it_prezzi" files "p_*.dta"
foreach f of local pfiles {
    append using "$TEMP/it_prezzi/`f'"
}
keep if inrange(date, $PANEL_START, $PANEL_END)
format date date_comu %td

* controllo: giorni senza file prezzi nel periodo
preserve
    contract date
    tsset date
    tsfill
    count if missing(_freq)
    if r(N) > 0 {
        di as error "Attenzione: `r(N)' giorni senza file prezzi MIMIT:"
        list date if missing(_freq), noobs
    }
restore

compress
save "$TEMP/it_prezzi_all.dta", replace

*==============================================================================
* B. ANAGRAFICA: unisco i file giornalieri e tengo l'ultimo record valido
*==============================================================================
foreach q in 2022_1_tr-an 2022_2_tr-an {
    local files : dir "$RAW/`q'" files "anagrafica_impianti_attivi-*.csv"
    foreach f of local files {
        local ds = ustrregexra("`f'", "^.*-|\.csv$", "")
        local d  = date("`ds'", "YMD")
        if missing(`d') | `d' < $PANEL_START | `d' > $PANEL_END continue

        mimit_read using "$RAW/`q'/`f'", right(4)
        local keepv ""
        foreach v in idimpianto bandiera tipo_impianto comune provincia latitudine longitudine {
            capture confirm variable `v'
            if !_rc local keepv "`keepv' `v'"
        }
        keep `keepv'
        gen date_an = `d'
        save "$TEMP/it_anagrafica/a_`ds'.dta", replace
    }
}

clear
local afiles : dir "$TEMP/it_anagrafica" files "a_*.dta"
foreach f of local afiles {
    append using "$TEMP/it_anagrafica/`f'"
}

foreach v in latitudine longitudine {
    replace `v' = subinstr(strtrim(`v'), ",", ".", .)
}
destring idimpianto latitudine longitudine, replace force
drop if missing(idimpianto)

* righe con separatori in eccesso negli indirizzi hanno coordinate non valide:
* preferisco l'ultimo record con coordinate valide
gen byte coord_ok = !missing(latitudine, longitudine)
bysort idimpianto (coord_ok date_an): keep if _n == _N
drop coord_ok date_an

capture confirm variable tipo_impianto
if !_rc gen byte highway = strpos(lower(tipo_impianto), "autostrad") > 0
else    gen byte highway = .

* zone extradoganali con accise diverse: da escludere
gen byte zona_franca = strpos(upper(comune), "LIVIGNO") > 0 | ///
                       strpos(upper(comune), "CAMPIONE") > 0

compress
save "$TEMP/it_anagrafica_clean.dta", replace

*==============================================================================
* C. MERGE prezzi + anagrafica e variabili armonizzate
*==============================================================================
use "$TEMP/it_prezzi_all.dta", clear
merge m:1 idimpianto using "$TEMP/it_anagrafica_clean.dta", ///
    keep(master match) gen(_m_anag)
gen byte in_anagrafica = _m_anag == 3
drop _m_anag
tab in_anagrafica

drop if zona_franca == 1
drop zona_franca

gen byte   country      = 1
gen str12  station_orig = string(idimpianto, "%12.0f")
rename provincia   region
rename latitudine  lat
rename longitudine lon
rename date_comu   date_update

keep country station_orig fuel date price date_update n_rec ///
     region comune bandiera highway lat lon in_anagrafica
order country station_orig fuel date price
compress
save "$TEMP/italy_clean.dta", replace
