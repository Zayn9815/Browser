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

    function applyDarkMode(enabled) {
        const existing = document.getElementById(STYLE_ID);
        if (enabled) {
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
        applyDarkMode(true);
    }
})();
