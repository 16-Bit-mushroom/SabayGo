"""Distances on the ground and on a route, with no database and no services.

Pure, so the booking path (a home pickup's pin, brief 2.6) and NAHGM's
geotag (6.3) share one route snapping without the import chain NAHGM
brings with it (trip_lifecycle -> boarding). A route is drawn straight
terminal to terminal, as the maps draw it and as NAHGM measures it.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres.

    Haversine rather than a planar approximation: at Davao's latitude the
    error from treating degrees as flat is small, but haversine costs
    nothing and removes a caveat you would otherwise have to defend.
    """
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def projection(lat: float, lon: float, alat: float, alon: float,
               blat: float, blon: float) -> float:
    """Where a point falls along the stretch a->b, 0..1, in a local flat
    frame (metres scale alike on both axes at this latitude)."""
    k = math.cos(math.radians((alat + blat) / 2))
    dx, dy = (blon - alon) * k, blat - alat
    span = dx * dx + dy * dy
    if span == 0:
        return 0.0
    t = ((lon - alon) * k * dx + (lat - alat) * dy) / span
    return min(1.0, max(0.0, t))


@dataclass(frozen=True)
class Snap:
    """A point's nearest place on a route."""
    offset_m: float         # how far the point is from the route line
    stretch: int            # k of the stretch stop k -> stop k+1
    from_start_m: float     # along the route from the first stop


def snap_to_route(lat: float, lon: float,
                  stops: Sequence[tuple[int, float, float]]) -> Snap | None:
    """The nearest point on the straight stretches between `stops`, given
    in route order as (stop_sequence, latitude, longitude). None for
    fewer than two stops: there is no line to snap to."""
    best: Snap | None = None
    travelled = 0.0
    for (seq, alat, alon), (_, blat, blon) in zip(stops, stops[1:]):
        length = haversine_m(alat, alon, blat, blon)
        t = projection(lat, lon, alat, alon, blat, blon)
        offset = haversine_m(lat, lon, alat + t * (blat - alat), alon + t * (blon - alon))
        if best is None or offset < best.offset_m:
            best = Snap(offset, seq, travelled + t * length)
        travelled += length
    return best
