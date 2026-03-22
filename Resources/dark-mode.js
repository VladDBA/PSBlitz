(function () {
    'use strict';

    const KEY = 'psblitz-dark';
    const root = document.documentElement;

    function apply(mode, btn) {
        if (mode === 'dark') {
            root.classList.add('dark-mode');
            if (btn) { btn.setAttribute('aria-pressed', 'true'); btn.textContent = 'Light'; }
        } else {
            root.classList.remove('dark-mode');
            if (btn) { btn.setAttribute('aria-pressed', 'false'); btn.textContent = 'Dark'; }
        }
    }

    document.addEventListener('DOMContentLoaded', function () {
        const btn = document.getElementById('dark-mode-toggle');
        if (!btn) {
            console.warn('dark-mode.js: toggle button not found');
            return;
        }

        const saved = localStorage.getItem(KEY);
        if (saved) {
            apply(saved, btn);
        } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            apply('dark', btn);
        }

        btn.addEventListener('click', function () {
            const isDark = root.classList.toggle('dark-mode');
            const mode = isDark ? 'dark' : 'light';
            localStorage.setItem(KEY, mode);
            apply(mode, btn);
        });
    });
})();