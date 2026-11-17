"""What the countries after the US share: one way to measure ground, one way to build a
trail catalogue, and offline packs for their parks.

At home the elevation is USGS 3DEP and the trails are the NPS layer. Abroad there is no
one agency for either, so the pipeline picks one method and applies it everywhere:

* ``elevation`` — the Copernicus GLO-30 surface model, cached per 1° tile, for trail
  profiles, park extremes and pack relief alike.
* ``trails`` — Norway's own route database (Kartverket's Turrutebasen) where it has routes,
  OpenStreetMap otherwise, measured exactly as the US catalogue is.
* ``packs`` — the offline pack steps (``fetch``/``derive``/``build --park jp-np-…``) for a
  park abroad, with ``outlines`` reading each park's outline straight from its source.

A country package calls these from its ``fetch`` and ``assemble``::

    trail_registry = ids.country_registry("no", "trails")
    trails = abroad.trails.build("no", parks, outlines, pois_by_park,
                                 online=context.online, registry=trail_registry)
    abroad.elevation.attach_extremes(places, outlines, online=context.online)

and adds ``trail_registry`` to ``Contribution.registries``. Nothing here knows a country's
places or guides beyond the park list and the outlines it is handed.
"""
