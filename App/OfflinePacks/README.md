# Offline park packs

Whatever is in this folder ships inside the app, as a folder reference, and the app's
**Park map** reads it (`docs/adr/0010-offline-packs-in-the-bundle.md`).

It is filled by the pipeline, not by hand, and everything but this file is gitignored:
packs are large and reproducible.

```bash
cd Pipeline
PYTHONPATH=src uv run python -m unigrids_pipeline fetch --park ZION
PYTHONPATH=src uv run python -m unigrids_pipeline derive --park ZION
PYTHONPATH=src uv run python -m unigrids_pipeline build --park ZION --skip-report
PYTHONPATH=src uv run python -m unigrids_pipeline package            # every built pack
PYTHONPATH=src uv run python -m unigrids_pipeline package --parks ZION,ACAD
```

An empty folder is a valid build: the app runs without offline maps and says so.
