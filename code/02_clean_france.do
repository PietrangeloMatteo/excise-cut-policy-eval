/*==============================================================================
  File   : 02_clean_france.do
  Input  : $RAW/PrixCarburants_annuel_2022.xml  (file oppure cartella con l'xml)
  Output : $TEMP/fr_changes.csv     (tutte le variazioni di prezzo, da Python)
           $TEMP/france_clean.dta   (stazione x carburante x giorno)
  Note   : l'XML registra ogni variazione di prezzo con data e ora (attributo
           maj). Per confrontarlo con il MIMIT ricostruisco il prezzo in vigore
           alle 8:00 di ogni giorno, portando avanti l'ultimo prezzo comunicato.
           Struttura attesa:
             <pdv id=".." latitude=".." longitude=".." cp=".." pop="R|A">
               <prix nom="Gazole" id="1" maj="2022-01-03 09:11:00" valeur="1.589"/>
==============================================================================*/

*------------------------------------------------------------------------------
* A. Python: XML -> csv delle variazioni di prezzo nel periodo del panel
*------------------------------------------------------------------------------
python:
import os, csv
import xml.etree.ElementTree as ET
from datetime import date, timedelta
from sfi import Macro

def _stata_to_iso(d):
    return (date(1960, 1, 1) + timedelta(days=int(float(d)))).isoformat()

def parse_fr_xml():
    raw   = Macro.getGlobal("RAW")
    temp  = Macro.getGlobal("TEMP")
    start = _stata_to_iso(Macro.getGlobal("PANEL_START"))
    stop  = _stata_to_iso(Macro.getGlobal("PANEL_END"))

    path = os.path.join(raw, "PrixCarburants_annuel_2022.xml")
    if os.path.isdir(path):
        xmls = [f for f in os.listdir(path) if f.lower().endswith(".xml")]
        if not xmls:
            raise FileNotFoundError("Nessun file .xml dentro " + path)
        path = os.path.join(path, xmls[0])
    print("Leggo:", path)

    out = os.path.join(temp, "fr_changes.csv")
    n_pdv = 0
    n_prix = 0
    with open(out, "w", newline="", encoding="utf-8") as fo:
        w = csv.writer(fo)
        w.writerow(["pdv_id", "cp", "pop", "lat", "lon", "fuel_fr", "maj", "valeur"])
        for event, elem in ET.iterparse(path, events=("end",)):
            if elem.tag != "pdv":
                continue
            n_pdv += 1
            attrs = [elem.get("id", ""), elem.get("cp", ""), elem.get("pop", ""),
                     elem.get("latitude", ""), elem.get("longitude", "")]
            for p in elem.iter("prix"):
                maj = (p.get("maj") or "").replace("T", " ")[:19]
                day = maj[:10]
                if day < start or day > stop:
                    continue
                w.writerow(attrs + [p.get("nom", ""), maj, p.get("valeur", "")])
                n_prix += 1
            elem.clear()
    print("Punti vendita letti:", n_pdv, "- variazioni di prezzo scritte:", n_prix)
end

capture confirm file "$TEMP/fr_changes.csv"
if _rc | $FR_REPARSE == 1 {
    python: parse_fr_xml()
}

*------------------------------------------------------------------------------
* B. Import e pulizia delle variazioni
*------------------------------------------------------------------------------
import delimited using "$TEMP/fr_changes.csv", varnames(1) ///
    stringcols(1 2 3 6 7) encoding("utf-8") clear

capture destring valeur lat lon, replace force
* prezzo: nei file recenti è in euro (1.589), in quelli vecchi in millesimi (1589)
replace valeur = valeur / 1000 if valeur > 10 & !missing(valeur)
rename valeur price
* coordinate: nel file sono moltiplicate per 100000
foreach v in lat lon {
    replace `v' = `v' / 100000 if abs(`v') > 1000 & !missing(`v')
}

* carburanti: gasolio = Gazole; benzina = $FR_PETROL (E10 o SP95)
tab fuel_fr
gen fuel = ""
replace fuel = "gasolio" if fuel_fr == "Gazole"
replace fuel = "benzina" if fuel_fr == "$FR_PETROL"
keep if fuel != ""

* territorio: escludo Corsica (IVA al 13%) e oltremare (regimi diversi)
replace cp = "0" + cp if strlen(cp) == 4
gen dep = substr(cp, 1, 2)
drop if inlist(dep, "20", "97", "98")

* allineamento temporale alla fotografia MIMIT delle 8:00:
* una variazione fatta alle 8:00 o dopo vale dal giorno successivo
gen double tc = clock(maj, "YMDhms")
drop if missing(tc) | missing(price)
gen date_change = dofc(tc)
gen date = date_change + (hh(tc) >= 8)
format date date_change %td

*------------------------------------------------------------------------------
* C. Caratteristiche della stazione (ultimo record)
*------------------------------------------------------------------------------
preserve
    bysort pdv_id (tc): keep if _n == _N
    gen byte highway = pop == "A"
    keep pdv_id dep highway lat lon
    tempfile fr_attr
    save `fr_attr'
restore

*------------------------------------------------------------------------------
* D. Panel giornaliero: ultima variazione efficace per giorno, poi riempio i
*    giorni senza variazioni portando avanti l'ultimo prezzo
*------------------------------------------------------------------------------
bysort pdv_id fuel date (tc): keep if _n == _N
keep pdv_id fuel date price date_change

egen long unit = group(pdv_id fuel)
tsset unit date
tsfill, full
bysort unit (pdv_id): replace pdv_id = pdv_id[_N]
bysort unit (fuel):   replace fuel   = fuel[_N]
bysort unit (date):   replace price       = price[_n-1]       if missing(price)
by unit:              replace date_change = date_change[_n-1] if missing(date_change)
drop if missing(price)        // giorni prima della prima variazione osservata
keep if inrange(date, $PANEL_START, $PANEL_END)
drop unit

merge m:1 pdv_id using `fr_attr', keep(master match) nogen

*------------------------------------------------------------------------------
* E. Variabili armonizzate con l'Italia
*------------------------------------------------------------------------------
gen byte country = 2
rename pdv_id      station_orig
rename dep         region
rename date_change date_update
gen byte in_anagrafica = 1

keep country station_orig fuel date price date_update region highway lat lon in_anagrafica
order country station_orig fuel date price
compress
save "$TEMP/france_clean.dta", replace
