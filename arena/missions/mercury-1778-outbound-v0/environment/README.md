# Mercury Historical Environment v0

`cliwoc-route-ensemble.v0.json` is generated from the official CLIWOC 2.1
core archive. It contains joint wind-speed/relative-direction histograms by
route leg and calendar month for observations from 1750 through 1805.

It is not a reconstructed 1778 weather field. The artifact represents
historical sampling variability, seasonality, joint wind conditions, and bin
discretization. It does not yet model log transcription error, position-error
posteriors, instrument bias, or climate nonstationarity.

Regenerate it with:

```sh
curl -L --fail -A 'yard-research/0.1' \
  -o /tmp/CLIWOC21CORE.zip \
  https://hs.pangaea.de/Projects/CLIWOC/CLIWOC21CORE.zip
python3 arena/tools/ingest_cliwoc.py \
  --core-zip /tmp/CLIWOC21CORE.zip \
  --output arena/missions/mercury-1778-outbound-v0/environment/cliwoc-route-ensemble.v0.json
```

The ingester rejects any archive whose SHA-256 is not
`b574909d59cc5d3f9bbf9b65eadf1358d5eae23d7f63dc8f8f0a740be8476be7`.

Source: Garcia-Herrera, Ricardo (2007), *CLIWOC Database 2.1 (final release,
original IMMA format)*, PANGAEA, <https://doi.org/10.1594/PANGAEA.743343>,
CC BY 3.0.
