# schemeconnect-data

Live scheme data for the SchemeConnect prototype (Central Government education
scholarship discovery app).

## What's here

- **`schemes.json`** — the current list of Central Government education
  schemes, scraped from the [National Scholarship Portal](https://scholarships.gov.in/All-Scholarships).
  The SchemeConnect app fetches this file directly at runtime via:
  `https://raw.githubusercontent.com/Saini111gaurav/schemeconnect-data/main/schemes.json`

- **`scraper/scrape_nsp.pl`** — the Perl script that produces `schemes.json`.
  Run it, then commit + push the updated file to publish new data.

## Scheme types covered

NSP splits schemes into three buckets via its own filter. This scraper pulls
the first two — both are genuinely Central Government schemes, just funded/run
differently:

| `schemeType` | What it means | Count | Scraped? |
|---|---|---|---|
| `central_sector` | Fully centrally funded and run (e.g. NMMS, INSPIRE, PMRF) | 31 | Yes |
| `centrally_sponsored` | Centrally funded, state-administered (e.g. Post-Matric SC/OBC/ST, PM YASASVI, Dr. Ambedkar EBC scholarship) — NSP lists one record per state/UT | ~105 | Yes |
| State Schemes | Genuinely state-funded, not central | 33 | **No** — out of scope per the project's own pilot-scope decision (Central Government schemes only) |

**Important coverage gap in the `centrally_sponsored` bucket:** it only
includes ~22 smaller states/UTs (Assam, Himachal Pradesh, Manipur, the Andaman
& Nicobar Islands, etc.). Larger states — UP, Bihar, Madhya Pradesh,
Karnataka, Tamil Nadu, Rajasthan, Gujarat, and others — run their own separate
scholarship portals for these same scheme types instead of routing through
NSP. No scrape of NSP can see those; a student in those states will only see
`central_sector` matches from this dataset, not `centrally_sponsored` ones.
This is a real limitation of the source, not a scraper bug.

`centrally_sponsored` records carry a `states` array (always exactly one
state/UT per record, taken directly from NSP's own grouping — not parsed out
of free text) so an app can filter to only the entries relevant to a given
user's state, the same way the existing Ishan Uday NE-region logic already
works.

## What this data does and doesn't cover

The scraper reliably keeps **scheme name, funding type, state (where
applicable), and application dates** current — if NSP adds a new scheme,
closes one, or shifts a deadline, the next scrape picks it up.

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
