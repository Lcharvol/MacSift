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
