#!/usr/bin/env python3
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Where the green chairs stand in the Luxembourg and the Tuileries: thick on
# the sand round the basins, thin across the rest of the garden, never on the
# lawns, in the water or against a tree.  Writes data/chairs.txt from the map
# chunks.  Run it again only if the map changes.
#
#   scripts/garden_chairs.py
import glob, math, random, re

PARKS = {
    'L': ('Jardin du Luxembourg', 700),
    'T': ('Jardin des Tuileries', 800),
}
# the basins: name or a point in it, and how many chairs gather round it
BASINS = {
    'L': [((48.846927, 2.337241), 170), ((48.848065, 2.338963), 22)],
    'T': [((48.862874, 2.329300), 120), ((48.864496, 2.324170), 170),
          ((48.863109, 2.330558), 30), ((48.862039, 2.329778), 30),
          ((48.863080, 2.327478), 24), ((48.863685, 2.327918), 24)],
}
SCATTER = {'L': 170, 'T': 170}
LAT0, LON0 = 48.8566, 2.3522
MX = 111320.0 * math.cos(math.radians(LAT0))
MZ = 110540.0


def xy(lat, lon):
    return ((lon - LON0) * MX, (lat - LAT0) * MZ)


def back(x, y):
    return (y / MZ + LAT0, x / MX + LON0)


def inside(p, poly):
    x, y = p
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def dist_seg(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def dist_poly(p, poly):
    return min(dist_seg(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


class Bounds:
    def __init__(self, poly, pad=0.0):
        self.x0 = min(q[0] for q in poly) - pad
        self.x1 = max(q[0] for q in poly) + pad
        self.y0 = min(q[1] for q in poly) - pad
        self.y1 = max(q[1] for q in poly) + pad

    def has(self, p):
        return self.x0 <= p[0] <= self.x1 and self.y0 <= p[1] <= self.y1


nodes, ways, rels, trees = {}, {}, [], []
for f in glob.glob('data/osm/chunks/*.osm'):
    t = open(f, encoding='utf8').read()
    for m in re.finditer(r'<node id="(\d+)"[^>]*?lat="([\d.]+)" lon="([\d.]+)"(/?)>', t):
        nodes[m[1]] = (float(m[2]), float(m[3]))
    for m in re.finditer(r'<node id="(\d+)"[^>]*?>(.*?)</node>', t, re.S):
        if 'k="natural" v="tree"' in m[2] and m[1] in nodes:
            trees.append(m[1])
    for w in re.findall(r'<way id="\d+".*?</way>', t, re.S):
        i = re.search(r'id="(\d+)"', w)[1]
        if i not in ways:
            ways[i] = (re.findall(r'<nd ref="(\d+)"', w), dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', w)))
    rels += re.findall(r'<relation id="\d+".*?</relation>', t, re.S)


def ring(i):
    return [xy(*nodes[n]) for n in ways[i][0] if n in nodes]


def outline(name):
    for i, (nd, tg) in ways.items():
        if tg.get('name') == name and nd[0] == nd[-1] and len(nd) > 8:
            return ring(i)
    for r in rels:
        if 'v="%s"' % name in r:
            pts = []
            for w in re.findall(r'<member type="way" ref="(\d+)" role="outer"', r):
                if w in ways:
                    pts += [ways[w][0]]
            # join the outer ways end to end
            line = list(pts.pop(0))
            while pts:
                for k, s in enumerate(pts):
                    if s[0] == line[-1]:
                        line += s[1:]
                    elif s[-1] == line[-1]:
                        line += s[-2::-1]
                    else:
                        continue
                    pts.pop(k)
                    break
                else:
                    break
            return [xy(*nodes[n]) for n in line if n in nodes]
    raise SystemExit('no outline for ' + name)


def blocked_shapes():
    areas, lines = [], []
    for i, (nd, tg) in ways.items():
        closed = len(nd) > 3 and nd[0] == nd[-1]
        n = tg.get('natural')
        hard = (tg.get('landuse') in ('grass', 'greenhouse_horticulture', 'flowerbed', 'meadow')
                or tg.get('leisure') in ('pitch', 'playground')
                or n in ('water', 'wood', 'scrub', 'grassland')
                or 'building' in tg or tg.get('amenity') == 'fountain'
                or tg.get('barrier') in ('wall', 'hedge'))
        if closed and hard:
            p = ring(i)
            if len(p) > 2:
                areas.append((p, Bounds(p, 2.0)))
        elif n == 'tree_row' or 'highway' in tg and tg['highway'] in (
                'steps', 'primary', 'secondary', 'tertiary', 'residential', 'service'):
            p = ring(i)
            if len(p) > 1:
                lines.append((p, Bounds(p, 3.0), 1.0 if n == 'tree_row' else 2.5))
    return areas, lines


AREAS, LINES = blocked_shapes()
TREES = [xy(*nodes[t]) for t in set(trees)]


def free(p, park, placed):
    if not inside(p, park):
        return False
    for a, b in AREAS:
        if b.has(p) and (inside(p, a) or dist_poly(p, a) < 0.7):
            return False
    for l, b, m in LINES:
        if b.has(p) and min(dist_seg(p, l[i], l[i + 1]) for i in range(len(l) - 1)) < m:
            return False
    for t in TREES:
        if abs(t[0] - p[0]) < 0.9 and abs(t[1] - p[1]) < 0.9:
            return False
    return all(math.hypot(p[0] - q[0], p[1] - q[1]) > 0.75 for q in placed)


def water_at(pt):
    p = xy(*pt)
    best = None
    for i, (nd, tg) in ways.items():
        if (tg.get('natural') == 'water' or tg.get('amenity') == 'fountain') and nd[0] == nd[-1]:
            r = ring(i)
            if len(r) > 2 and inside(p, r):
                best = r
    if best is None:
        raise SystemExit('no water at %r' % (pt,))
    return best


def heading_to(p, q):
    return math.degrees(math.atan2(q[0] - p[0], q[1] - p[1])) % 360.0


random.seed(1848)
out = ['# The green chairs of the Luxembourg (L) and the Tuileries (T): made by',
       '# scripts/garden_chairs.py from OpenStreetMap (© OpenStreetMap contributors, ODbL).',
       '# park lat lon heading (degrees: the way the chair faces)']
for key, (name, _) in PARKS.items():
    park = outline(name)
    box = Bounds(park)
    placed = []
    rows = []

    def add(p, h):
        placed.append(p)
        la, lo = back(*p)
        rows.append('%s %.6f %.6f %.0f' % (key, la, lo, h % 360.0))

    for pt, want in BASINS[key]:
        w = water_at(pt)
        mid = (sum(q[0] for q in w) / len(w), sum(q[1] for q in w) / len(w))
        got = tries = 0
        while got < want and tries < want * 200:
            tries += 1
            # a spot by the rim: most close to it, some further back
            k = random.randrange(len(w))
            e0, e1 = w[k], w[(k + 1) % len(w)]
            f = random.random()
            e = (e0[0] + f * (e1[0] - e0[0]), e0[1] + f * (e1[1] - e0[1]))
            dx, dy = e[0] - mid[0], e[1] - mid[1]
            d = math.hypot(dx, dy) or 1.0
            back_off = 1.2 + min(16.0, random.expovariate(1.0 / 3.5))
            c = (e[0] + dx / d * back_off, e[1] + dy / d * back_off)
            face = heading_to(c, mid)
            size = random.choice((1, 1, 1, 2, 2, 3, 4))
            lean = random.gauss(0.0, 22.0)
            for n in range(size):
                p = (c[0] + random.uniform(-1.3, 1.3) * (n > 0), c[1] + random.uniform(-1.3, 1.3) * (n > 0))
                if dist_poly(p, w) > 1.0 and not inside(p, w) and free(p, park, placed):
                    h = face + lean + random.gauss(0.0, 14.0)
                    if size > 1 and random.random() < 0.3:
                        h = heading_to(p, c) if n > 0 else h   # turned to the others
                    add(p, h)
                    got += 1
    got = tries = 0
    while got < SCATTER[key] and tries < 40000:
        tries += 1
        c = (random.uniform(box.x0, box.x1), random.uniform(box.y0, box.y1))
        h0 = random.uniform(0.0, 360.0)
        size = random.choice((1, 1, 2, 2, 3))
        for n in range(size):
            p = (c[0] + random.uniform(-1.2, 1.2) * (n > 0), c[1] + random.uniform(-1.2, 1.2) * (n > 0))
            if free(p, park, placed):
                add(p, h0 + random.gauss(0.0, 35.0))
                got += 1
    print(key, name, len(rows), 'chairs')
    out += rows
open('data/chairs.txt', 'w').write('\n'.join(out) + '\n')
