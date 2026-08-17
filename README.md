# schemeconnect-data

Live scheme data for the SchemeConnect prototype (Central Government education
scholarship discovery app).

## What's here

- **`schemes.json`** — the current list of Central Sector scholarship schemes,
  scraped from the [National Scholarship Portal](https://scholarships.gov.in/All-Scholarships)
  (name, ministry, application open/close dates, status, official guidelines link).
  The SchemeConnect app fetches this file directly at runtime via:
  `https://raw.githubusercontent.com/Saini111gaurav/schemeconnect-data/main/schemes.json`

- **`scraper/scrape_nsp.pl`** — the Perl script that produces `schemes.json`.
  Run it, then commit + push the updated file to publish new data.

## What this data does and doesn't cover

The scraper reliably keeps **scheme name, ministry, and application dates**
current — if NSP adds a new scheme, closes one, or shifts a deadline, the next
scrape picks it up.

It does **not** extract eligibility rules (income caps, category, gender,
education level) — those live as prose inside each scheme's PDF guidelines,
not in structured form on the listing page. Eligibility-matching rules are
maintained separately in the app itself and mapped onto this list by scheme
name/id.

## Updating the data

```
cd scraper
perl scrape_nsp.pl
cp schemes_live.json ../schemes.json
cd ..
git add schemes.json
git commit -m "Update scheme data"
git push
```
