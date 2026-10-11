.pragma library

function score(text, query) {
    const haystack = String(text).toLowerCase();
    const needle = query.trim().toLowerCase();
    if (!needle)
        return 0;
    if (haystack === needle)
        return 1000;
    if (haystack.startsWith(needle))
        return 500;
    const position = haystack.indexOf(needle);
    if (position >= 0)
        return 300 - position;
    let cursor = 0;
    for (const character of haystack) {
        if (character === needle[cursor])
            cursor++;
        if (cursor === needle.length)
            return 100;
    }
    return -1;
}

function filterRows({ rows, query, scope }) {
    return rows.filter(row => scope === "All" || row.category === scope)
        .map(row => ({ row, rank: score(row.search || row.title, query) }))
        .filter(item => item.rank >= 0)
        .sort((a, b) => b.rank - a.rank || (a.row.priority || 0) - (b.row.priority || 0)
            || a.row.title.localeCompare(b.row.title))
        .slice(0, 80).map(item => item.row);
}
