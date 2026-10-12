/* MacSift landing — progressive enhancement only. Nothing here is required
   for the page to be readable; it all degrades to a working static page. */

// ---------------------------------------------------------------- Theme ----
// The initial class is set by the inline script in <head> to avoid a flash.
// Here we only wire the toggle and track the system preference.
(function () {
    const root = document.documentElement;
    const toggle = document.getElementById('theme-toggle');
    const media = window.matchMedia('(prefers-color-scheme: dark)');

    const syncLabel = () => {
        if (!toggle) return;
        const dark = root.classList.contains('dark');
        toggle.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
    };

    toggle?.addEventListener('click', () => {
        const dark = root.classList.toggle('dark');
        try {
            localStorage.setItem('macsift-theme', dark ? 'dark' : 'light');
        } catch (e) {
            /* Private browsing — the toggle still works for this page view. */
        }
        syncLabel();
    });

    // Follow the OS only while the visitor hasn't made an explicit choice.
    media.addEventListener('change', (e) => {
        let stored = null;
        try {
            stored = localStorage.getItem('macsift-theme');
        } catch (err) {}
        if (stored) return;
        root.classList.toggle('dark', e.matches);
        syncLabel();
    });

    syncLabel();
})();

// ------------------------------------------------------------------ Nav ----
// Give the fixed nav a background only once the page has scrolled.
(function () {
    const nav = document.getElementById('nav');
    if (!nav) return;

    let ticking = false;
    const update = () => {
        nav.classList.toggle('nav--scrolled', window.scrollY > 8);
        ticking = false;
    };

    window.addEventListener('scroll', () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(update);
    }, { passive: true });

    update();
})();

// ----------------------------------------------------------------- Tabs ----
// Install section. Follows the APG tabs pattern: roving arrow keys, and
// aria-selected / hidden kept in sync.
(function () {
    const list = document.querySelector('.tabs__list');
    if (!list) return;

    const triggers = Array.from(list.querySelectorAll('.tabs__trigger'));

    const select = (trigger) => {
        triggers.forEach((t) => {
            const selected = t === trigger;
            t.setAttribute('aria-selected', String(selected));
            t.tabIndex = selected ? 0 : -1;
            const panel = document.getElementById(t.getAttribute('aria-controls'));
            if (panel) panel.hidden = !selected;
        });
    };

    triggers.forEach((trigger, i) => {
        trigger.tabIndex = trigger.getAttribute('aria-selected') === 'true' ? 0 : -1;
        trigger.addEventListener('click', () => select(trigger));
        trigger.addEventListener('keydown', (e) => {
            if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
            e.preventDefault();
            const next = triggers[(i + (e.key === 'ArrowRight' ? 1 : -1) + triggers.length) % triggers.length];
            select(next);
            next.focus();
        });
    });
})();

// --------------------------------------------------------------- Reveal ----
// Fade sections in as they enter the viewport. Elements are made visible
// immediately when IntersectionObserver is unavailable, so content is never
// stuck at opacity 0.
(function () {
    const targets = document.querySelectorAll('.reveal');
    if (!targets.length) return;

    if (!('IntersectionObserver' in window)) {
        targets.forEach((el) => el.classList.add('is-visible'));
        return;
    }

    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            entry.target.classList.add('is-visible');
            observer.unobserve(entry.target);
        });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.05 });

    targets.forEach((el) => observer.observe(el));
})();

// ----------------------------------------------------------------- Copy ----
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

// ---------------------------------------------------------------- Stats ----
// Fetched live from the GitHub REST API (unauthenticated, 60 req/h per IP).
// Both calls fail silently: if GitHub is unreachable or rate-limits us the
// cards just keep their `—` placeholder instead of breaking the page.
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
