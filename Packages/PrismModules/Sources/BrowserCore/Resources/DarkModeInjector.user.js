(() => {
    'use strict';
    const STYLE_ID = '__prism_dark_mode_style';
    const DARK_CSS = `
        :root, html {
            color-scheme: dark !important;
            background-color: #0e0e14 !important;
            filter: invert(0.92) hue-rotate(180deg) !important;
        }
        img, video, picture, canvas, svg, iframe, embed, object,
        [style*="background-image"], .prism-preserve-media {
            filter: invert(1) hue-rotate(180deg) !important;
        }
        img[src$=".svg"] {
            filter: none !important;
        }
    `;

    function isAlreadyDarkPage() {
        try {
            const metaScheme = document.querySelector('meta[name="color-scheme"]');
            if (metaScheme && /dark/i.test(metaScheme.content || '') && !/light/i.test(metaScheme.content || '')) {
                return true;
            }
            const targets = [document.body, document.documentElement].filter(Boolean);
            for (const el of targets) {
                const bg = window.getComputedStyle(el).backgroundColor;
                const m = bg && bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
                if (m) {
                    const alpha = m[4] !== undefined ? parseFloat(m[4]) : 1;
                    if (alpha > 0.2) {
                        const r = parseInt(m[1], 10);
                        const g = parseInt(m[2], 10);
                        const b = parseInt(m[3], 10);
                        const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
                        if (luminance < 0.28) return true;
                        return false;
                    }
                }
            }
        } catch (_) {}
        return false;
    }

    function applyDarkMode(enabled) {
        const existing = document.getElementById(STYLE_ID);
        if (enabled) {
            if (isAlreadyDarkPage()) {
                if (existing) existing.remove();
                return;
            }
            if (!existing) {
                const style = document.createElement('style');
                style.id = STYLE_ID;
                style.textContent = DARK_CSS;
                const parent = document.head || document.documentElement;
                if (parent) {
                    parent.appendChild(style);
                }
            }
        } else if (existing) {
            existing.remove();
        }
    }

    window.__prismSetDarkMode = applyDarkMode;

    if (window.__prismInitialDarkMode === true) {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => applyDarkMode(true), { once: true });
        } else {
            applyDarkMode(true);
        }
    }
})();
