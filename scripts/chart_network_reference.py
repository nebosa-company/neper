"""Reference for e.gfx.chart.network_layout (D2112): the same Fruchterman-Reingold
steps in Python floats, printing the coordinates gfx_chart_network checks, plus the
karate-club edge list and NetworkX's Louvain communities used by the gallery."""
import math


def layout(n, edges, bounds, iterations):
    k = math.sqrt(1.0 / n)
    pos = []
    for i in range(n):
        radius = 0.45 * math.sqrt((i + 0.5) / n)
        angle = i * 2.399963229728653
        pos.append([0.5 + radius * math.cos(angle), 0.5 + radius * math.sin(angle)])
    for step in range(iterations):
        temperature = 0.1 * (1.0 - step / iterations)
        disp = [[0.0, 0.0] for _ in range(n)]
        for i in range(n):
            for j in range(i + 1, n):
                dx, dy = pos[i][0] - pos[j][0], pos[i][1] - pos[j][1]
                d = max(math.sqrt(dx * dx + dy * dy), 1e-9)
                f = k * k / d / d
                disp[i][0] += dx * f; disp[i][1] += dy * f
                disp[j][0] -= dx * f; disp[j][1] -= dy * f
        for u, v in edges:
            if u == v:
                continue
            dx, dy = pos[u][0] - pos[v][0], pos[u][1] - pos[v][1]
            f = math.sqrt(dx * dx + dy * dy) / k
            disp[u][0] -= dx * f; disp[u][1] -= dy * f
            disp[v][0] += dx * f; disp[v][1] += dy * f
        for i in range(n):
            length = math.hypot(*disp[i]) if False else math.sqrt(disp[i][0] ** 2 + disp[i][1] ** 2)
            if length > 0:
                limited = min(length, temperature)
                pos[i][0] += disp[i][0] / length * limited
                pos[i][1] += disp[i][1] / length * limited
    x0, y0, w, h = bounds
    xs, ys = [p[0] for p in pos], [p[1] for p in pos]
    span = max(xs) - min(xs)
    if max(ys) - min(ys) > span * h / w:
        span = (max(ys) - min(ys)) * w / h
    scale = w / span if span > 0 else 0.0
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    return [(x0 + w / 2 + (p[0] - cx) * scale, y0 + h / 2 + (p[1] - cy) * scale) for p in pos]


if __name__ == "__main__":
    small = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 3)]
    for x, y in layout(6, small, (0.0, 0.0, 200.0, 100.0), 50):
        print(f"{x:.4f} {y:.4f}")
    import networkx as nx
    g = nx.karate_club_graph()
    edges = sorted((min(u, v), max(u, v)) for u, v in g.edges())
    print("karate edges", len(edges), [u for u, _ in edges], [v for _, v in edges])
    from networkx.algorithms.community import louvain_communities, modularity
    parts = louvain_communities(g, weight=None, seed=1)
    print("networkx louvain modularity %.4f" % modularity(g, parts, weight=None), sorted(len(p) for p in parts))
