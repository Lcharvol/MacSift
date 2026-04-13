// Minimal landing-page interactions — no framework, no tracking.

// Copy buttons in the Install section.
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
            }, 1600);
        } catch (err) {
            console.error('Clipboard write failed', err);
        }
    });
});

// Smooth scroll for same-page anchors (in case browser doesn't honor
// scroll-behavior: smooth for programmatic navigation).
document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', (e) => {
        const href = anchor.getAttribute('href');
        if (!href || href === '#') return;
        const target = document.querySelector(href);
        if (!target) return;
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});

// Live GitHub stats — best effort, falls back silently if rate limited.
(async function fetchGithubMeta() {
    try {
        const res = await fetch('https://api.github.com/repos/Lcharvol/MacSift');
        if (!res.ok) return;
        const data = await res.json();
        const starLink = document.querySelector('.btn--ghost');
        if (starLink && typeof data.stargazers_count === 'number' && data.stargazers_count > 0) {
            const count = data.stargazers_count;
            const label = starLink.querySelector('svg')?.nextSibling ?? starLink.lastChild;
            starLink.insertAdjacentHTML(
                'beforeend',
                ` <span style="margin-left:4px; padding:2px 8px; background:rgba(255,255,255,0.06); border-radius:10px; font-size:12px; font-weight:600;">${count}</span>`
            );
        }
    } catch (_) {
        // ignore — GitHub API may be rate-limited
    }
})();
