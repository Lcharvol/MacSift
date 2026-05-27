// Copy buttons in the Install block.
document.querySelectorAll('.copy-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
        const text = btn.dataset.copy?.replace(/&#10;/g, '\n') ?? '';
        try {
            await navigator.clipboard.writeText(text);
            const original = btn.textContent;
            btn.textContent = 'Copied';
            btn.classList.add('copied');
            setTimeout(() => {
                btn.textContent = original;
                btn.classList.remove('copied');
            }, 1500);
        } catch (err) {
            console.error('Clipboard write failed', err);
        }
    });
});

// OSS stats — fetched live from the GitHub REST API (unauthenticated, 60 req/h
// per IP). Both calls fail silently: if GitHub is unreachable or rate-limits
// us the cards just keep their `—` placeholder instead of breaking the page.
const formatCount = (n) => (n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n));

fetch('https://api.github.com/repos/Lcharvol/MacSift')
    .then((r) => r.json())
    .then((d) => {
        if (typeof d.stargazers_count !== 'number') return;
        const el = document.getElementById('stat-stars');
        if (el) el.textContent = formatCount(d.stargazers_count);
    })
    .catch(() => {});

fetch('https://api.github.com/repos/Lcharvol/MacSift/releases?per_page=100')
    .then((r) => r.json())
    .then((releases) => {
        if (!Array.isArray(releases)) return;
        // Sum download_count across every asset of every release. We ship
        // both MacSift.zip and MacSift-X.Y.Z.zip per release, and a single
        // user only downloads one — counting both gives the true install total.
        let total = 0;
        for (const rel of releases) {
            for (const a of rel.assets || []) total += a.download_count || 0;
        }
        const el = document.getElementById('stat-installs');
        if (el) el.textContent = formatCount(total);
    })
    .catch(() => {});
