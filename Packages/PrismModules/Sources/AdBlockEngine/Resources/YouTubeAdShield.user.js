(() => {
    'use strict';

    const host = (window.location && window.location.hostname || '').toLowerCase();
    const isYouTube =
        host === 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host === 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');

    if (!isYouTube) return;
    if (window.__prismYouTubeAdShieldLoaded) return;
    window.__prismYouTubeAdShieldLoaded = true;

    const isEnabled = () => window.__prismYouTubeAdShieldEnabled !== false;

    const AD_KEYS = new Set([
        'adPlacements',
        'playerAds',
        'adSlots',
        'adBreakHeartbeatParams',
        'adBreakParams',
    ]);

    const AD_RENDERER_KEYS = new Set([
        'adSlotRenderer',
        'inFeedAdLayoutRenderer',
        'promotedSparklesWebRenderer',
        'promotedSparklesTextSearchRenderer',
        'promotedVideoRenderer',
        'displayAdRenderer',
        'compactPromotedVideoRenderer',
        'bannerPromoRenderer',
        'statementBannerRenderer',
        'mealbarPromoRenderer',
        'playerLegacyDesktopWatchAdsRenderer',
        'actionCompanionAdRenderer',
    ]);

    function pruneAds(node, depth = 0) {
        if (!node || typeof node !== 'object' || depth > 14) return node;
        if (Array.isArray(node)) {
            let writeIdx = 0;
            for (let i = 0; i < node.length; i++) {
                const item = node[i];
                if (item && typeof item === 'object' && !Array.isArray(item)) {
                    let isAdItem = false;
                    for (const key of Object.keys(item)) {
                        if (AD_RENDERER_KEYS.has(key)) {
                            isAdItem = true;
                            break;
                        }
                    }
                    if (isAdItem) continue;
                }
                pruneAds(item, depth + 1);
                node[writeIdx++] = item;
            }
            node.length = writeIdx;
            return node;
        }

        for (const key of Object.keys(node)) {
            if (AD_KEYS.has(key) || AD_RENDERER_KEYS.has(key)) {
                delete node[key];
                continue;
            }
            const val = node[key];
            if (val && typeof val === 'object') {
                pruneAds(val, depth + 1);
            }
        }
        return node;
    }

    // 1. Intercept JSON.parse for YouTube player/browse payloads
    const originalJSONParse = JSON.parse;
    JSON.parse = function prismJSONParse(text, reviver) {
        const parsed = originalJSONParse.call(this, text, reviver);
        if (isEnabled() && parsed && typeof parsed === 'object') {
            if (
                'adPlacements' in parsed ||
                'playerAds' in parsed ||
                'adSlots' in parsed ||
                'contents' in parsed ||
                'onResponseReceivedActions' in parsed
            ) {
                try {
                    pruneAds(parsed, 0);
                } catch (_) {}
            }
        }
        return parsed;
    };

    // 2. Intercept window.fetch for /youtubei/v1/player, /next, /browse
    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
        window.fetch = async function prismFetch(input, init) {
            const url = typeof input === 'string' ? input : (input && input.url) || '';
            const response = await originalFetch.apply(this, arguments);
            if (
                isEnabled() &&
                (url.includes('/youtubei/v1/player') ||
                 url.includes('/youtubei/v1/next') ||
                 url.includes('/youtubei/v1/browse'))
            ) {
                try {
                    const cloned = response.clone();
                    const json = await cloned.json();
                    pruneAds(json, 0);
                    return new Response(JSON.stringify(json), {
                        status: response.status,
                        statusText: response.statusText,
                        headers: response.headers,
                    });
                } catch (_) {
                    return response;
                }
            }
            return response;
        };
    }

    // 3. Intercept window.ytInitialPlayerResponse and window.ytInitialData assignments
    function definePrunedGlobal(propName) {
        let currentValue = window[propName];
        if (currentValue && typeof currentValue === 'object' && isEnabled()) {
            try { pruneAds(currentValue, 0); } catch (_) {}
        }
        try {
            Object.defineProperty(window, propName, {
                configurable: true,
                enumerable: true,
                get() {
                    return currentValue;
                },
                set(next) {
                    if (next && typeof next === 'object' && isEnabled()) {
                        try { pruneAds(next, 0); } catch (_) {}
                    }
                    currentValue = next;
                },
            });
        } catch (_) {}
    }
    definePrunedGlobal('ytInitialPlayerResponse');
    definePrunedGlobal('ytInitialData');

    // 4. Inject cosmetic CSS hiding ad overlays and promoted cards
    const STYLE_ID = 'prism-yt-ad-shield-css';
    function ensureCosmeticCSS() {
        if (!isEnabled() || document.getElementById(STYLE_ID)) return;
        const style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = `
            .ytp-ad-module,
            .ytp-ad-overlay-container,
            .ytp-ad-player-overlay,
            .ytp-ad-progress-list,
            .ad-created .video-ads,
            ytd-ad-slot-renderer,
            ytd-in-feed-ad-layout-renderer,
            ytd-banner-promo-renderer,
            ytd-promoted-sparkles-web-renderer,
            ytd-display-ad-renderer,
            ytm-promoted-sparkles-web-renderer,
            ytm-promoted-sparkles-text-search-renderer,
            ytm-companion-ad-renderer,
            ytm-mealbar-promo-renderer,
            ad-slot-renderer,
            #masthead-ad,
            #player-ads {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                max-height: 0 !important;
                opacity: 0 !important;
                pointer-events: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    }

    // 5. Event-driven zero-polling MutationObserver to auto-skip any fallback ad playback
    let savedUserMuted = null;

    function handlePlayerAdState() {
        if (!isEnabled()) return;
        const player = document.querySelector('#movie_player, .html5-video-player');
        if (!player) return;

        const isAdPlaying =
            player.classList.contains('ad-showing') ||
            player.classList.contains('ad-interrupting');

        const video = player.querySelector('video');

        if (isAdPlaying) {
            const skipBtn = document.querySelector(
                '.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern, button.ytp-ad-skip-button-modern'
            );
            if (skipBtn && typeof skipBtn.click === 'function') {
                skipBtn.click();
            }
            if (video) {
                if (savedUserMuted === null) {
                    savedUserMuted = video.muted;
                }
                video.muted = true;
                if (Number.isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.1) {
                    try {
                        video.currentTime = video.duration;
                    } catch (_) {}
                }
            }
        } else if (savedUserMuted !== null && video) {
            video.muted = savedUserMuted;
            savedUserMuted = null;
        }
    }

    function startObserver() {
        ensureCosmeticCSS();
        handlePlayerAdState();

        const target = document.documentElement || document.body;
        if (!target) return;

        const observer = new MutationObserver(() => {
            if (!isEnabled()) return;
            ensureCosmeticCSS();
            handlePlayerAdState();
        });
        observer.observe(target, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['class'],
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startObserver, { once: true });
    } else {
        startObserver();
    }
})();
