(() => {
    'use strict';

    const GUARD = Symbol.for('__prismdm_media_sniffer_v1');
    if (window[GUARD]) return;
    Object.defineProperty(window, GUARD, { value: true, enumerable: false, configurable: false });

    const BRIDGE_NAME = 'prismMediaBridge';
    const SCHEMA_VERSION = 1;
    const MANIFEST_WINDOW_MS = 15000;

    const state = {
        nextVideoId: 1,
        videoMap: new WeakMap(),
        idToVideo: new Map(),
        recentManifests: [],
        frameHasEME: false
    };

    function safeOrigin() {
        try {
            return window.location.origin && window.location.origin !== 'null'
                ? window.location.origin
                : window.location.href;
        } catch (_) {
            return '';
        }
    }

    function safeHref() {
        try {
            return window.location.href || '';
        } catch (_) {
            return '';
        }
    }

    function safeTitle() {
        try {
            return (document.title || '').slice(0, 240);
        } catch (_) {
            return '';
        }
    }

    function postEvent(eventName, payload) {
        try {
            const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[BRIDGE_NAME];
            if (!bridge) return;
            bridge.postMessage({
                schemaVersion: SCHEMA_VERSION,
                event: eventName,
                frameOrigin: safeOrigin(),
                pageReferer: safeHref(),
                pageTitle: safeTitle(),
                timestampMs: Date.now(),
                payload: payload
            });
        } catch (_) {}
    }

    function resolveAbsoluteURL(raw) {
        if (!raw || typeof raw !== 'string') return null;
        const trimmed = raw.trim();
        if (!trimmed) return null;
        if (trimmed.startsWith('blob:')) return trimmed;
        try {
            const parsed = new URL(trimmed, window.location.href);
            if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
                return parsed.href;
            }
        } catch (_) {}
        return null;
    }

    function classifyMediaURL(urlString, mimeType) {
        if (!urlString) return null;
        const lowerURL = urlString.toLowerCase();
        const lowerMime = (mimeType || '').toLowerCase();

        if (lowerMime.includes('mpegurl') || /\.m3u8(\?|$|#)/.test(lowerURL)) return 'm3u8';
        if (lowerMime.includes('dash+xml') || /\.mpd(\?|$|#)/.test(lowerURL)) return 'mpd';
        if (lowerMime.includes('video/mp4') || /\.mp4(\?|$|#)/.test(lowerURL)) return 'mp4';
        if (lowerMime.includes('video/webm') || /\.webm(\?|$|#)/.test(lowerURL)) return 'webm';
        return null;
    }

    function pruneManifests() {
        const cutoff = Date.now() - MANIFEST_WINDOW_MS;
        state.recentManifests = state.recentManifests.filter((item) => item.ts >= cutoff);
    }

    function recordNetworkCandidate(rawURL, mimeType) {
        const resolved = resolveAbsoluteURL(rawURL);
        if (!resolved || resolved.startsWith('blob:')) return;
        const hint = classifyMediaURL(resolved, mimeType);
        if (!hint) return;

        pruneManifests();
        if (hint === 'm3u8' || hint === 'mpd') {
            state.recentManifests.push({ url: resolved, hint: hint, ts: Date.now() });
            if (state.recentManifests.length > 20) {
                state.recentManifests.shift();
            }
        }

        postEvent('MEDIA_CANDIDATE_DETECTED', {
            candidateId: 'net_' + hint + '_' + Math.abs(hashString(resolved)),
            streamUrl: resolved,
            containerHint: hint,
            mimeType: mimeType || null,
            isBlob: false,
            isDRMProtected: state.frameHasEME
        });
    }

    function hashString(str) {
        let h = 0;
        for (let i = 0; i < str.length; i++) {
            h = ((h << 5) - h + str.charCodeAt(i)) | 0;
        }
        return h;
    }

    function ensureVideoId(video) {
        let id = state.videoMap.get(video);
        if (!id) {
            id = '__prism_vid_' + (state.nextVideoId++);
            state.videoMap.set(video, id);
            state.idToVideo.set(id, video);
        }
        return id;
    }

    function isVideoDRM(video) {
        try {
            if (state.frameHasEME) return true;
            if (video && video.mediaKeys != null) return true;
            if (video && video.dataset && video.dataset.prismDrm === '1') return true;
        } catch (_) {}
        return false;
    }

    function getViewportRect(el) {
        try {
            const r = el.getBoundingClientRect();
            return { x: r.x, y: r.y, width: r.width, height: r.height };
        } catch (_) {
            return null;
        }
    }

    function extractVideoPlayableURL(video) {
        if (!video) return null;
        const direct = resolveAbsoluteURL(video.currentSrc || video.src);
        if (direct && !direct.startsWith('blob:')) {
            return direct;
        }
        const sources = video.querySelectorAll ? video.querySelectorAll('source[src]') : [];
        for (const s of sources) {
            const candidate = resolveAbsoluteURL(s.getAttribute('src'));
            if (candidate && !candidate.startsWith('blob:')) {
                return candidate;
            }
        }
        pruneManifests();
        if (state.recentManifests.length > 0) {
            return state.recentManifests[state.recentManifests.length - 1].url;
        }
        return null;
    }

    function inspectVideoElement(video) {
        if (!video || video.nodeName !== 'VIDEO') return;
        const vidId = ensureVideoId(video);

        // Enforce inline playback so PrismPlayer controls fullscreen transitions
        try {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', '');
            }
            if (!video.hasAttribute('webkit-playsinline')) {
                video.setAttribute('webkit-playsinline', '');
            }
            video.playsInline = true;
        } catch (_) {}

        if (!video.__prismObserved) {
            Object.defineProperty(video, '__prismObserved', { value: true, enumerable: false });
            video.addEventListener('encrypted', () => {
                try { video.dataset.prismDrm = '1'; } catch (_) {}
                state.frameHasEME = true;
                postEvent('DRM_STREAM_DETECTED', {
                    videoElementId: vidId,
                    isDRMProtected: true,
                    hasMediaKeys: true
                });
            }, { passive: true });

            video.addEventListener('loadedmetadata', () => {
                reportVideoCandidate(video);
            }, { passive: true });
        }

        reportVideoCandidate(video);
    }

    function reportVideoCandidate(video) {
        const vidId = ensureVideoId(video);
        const drm = isVideoDRM(video);
        const rawSrc = video.currentSrc || video.src || '';

        if (rawSrc.startsWith('blob:')) {
            pruneManifests();
            postEvent('BLOB_SOURCE_ATTACHED', {
                blobUrl: rawSrc,
                videoElementId: vidId,
                recentNetworkManifests: state.recentManifests.map((m) => m.url),
                hasMediaKeys: drm,
                isDRMProtected: drm,
                videoWidth: video.videoWidth || null,
                videoHeight: video.videoHeight || null,
                durationSeconds: Number.isFinite(video.duration) ? video.duration : null,
                elementRectViewport: getViewportRect(video)
            });
            return;
        }

        const resolved = extractVideoPlayableURL(video);
        if (!resolved) return;
        const hint = classifyMediaURL(resolved, '') || 'mp4';

        postEvent('MEDIA_CANDIDATE_DETECTED', {
            candidateId: vidId,
            videoElementId: vidId,
            streamUrl: resolved,
            containerHint: hint,
            mimeType: null,
            isBlob: false,
            isDRMProtected: drm,
            videoWidth: video.videoWidth || null,
            videoHeight: video.videoHeight || null,
            durationSeconds: Number.isFinite(video.duration) ? video.duration : null,
            elementRectViewport: getViewportRect(video)
        });
    }

    function attemptFullscreenIntercept(video) {
        if (!video || isVideoDRM(video)) return false;
        const resolved = extractVideoPlayableURL(video);
        if (!resolved) return false;

        const vidId = ensureVideoId(video);
        const wasPlaying = !video.paused && !video.ended;
        const currentTime = Number.isFinite(video.currentTime) ? video.currentTime : 0;
        const rate = Number.isFinite(video.playbackRate) ? video.playbackRate : 1.0;

        try { video.pause(); } catch (_) {}

        postEvent('FULLSCREEN_INTERCEPTED', {
            videoElementId: vidId,
            resolvedStreamUrl: resolved,
            containerHint: classifyMediaURL(resolved, '') || 'mp4',
            currentTimeSeconds: currentTime,
            playbackRate: rate,
            wasPlaying: wasPlaying,
            isDRMProtected: false,
            videoWidth: video.videoWidth || null,
            videoHeight: video.videoHeight || null,
            durationSeconds: Number.isFinite(video.duration) ? video.duration : null
        });
        return true;
    }

    // Expose safe pause command invoked by Swift MediaInterceptorCoordinator on handoff
    Object.defineProperty(window, '__prismPauseInterceptedVideo', {
        enumerable: false,
        configurable: true,
        value: function(videoElementId) {
            try {
                const target = state.idToVideo.get(videoElementId);
                if (target) {
                    target.pause();
                } else {
                    document.querySelectorAll('video').forEach((v) => {
                        try { v.pause(); } catch (_) {}
                    });
                }
            } catch (_) {}
        }
    });

    // 1. EME / DRM Detection Hooks (Never intercept FairPlay / Widevine / PlayReady)
    if (navigator && typeof navigator.requestMediaKeySystemAccess === 'function') {
        const origRequestMKSA = navigator.requestMediaKeySystemAccess.bind(navigator);
        navigator.requestMediaKeySystemAccess = function() {
            return origRequestMKSA.apply(this, arguments).then((access) => {
                state.frameHasEME = true;
                postEvent('DRM_STREAM_DETECTED', { isDRMProtected: true, hasMediaKeys: true });
                return access;
            });
        };
    }

    if (typeof HTMLMediaElement !== 'undefined' && HTMLMediaElement.prototype) {
        if (typeof HTMLMediaElement.prototype.setMediaKeys === 'function') {
            const origSetKeys = HTMLMediaElement.prototype.setMediaKeys;
            HTMLMediaElement.prototype.setMediaKeys = function(keys) {
                if (keys) {
                    state.frameHasEME = true;
                    try { this.dataset.prismDrm = '1'; } catch (_) {}
                    postEvent('DRM_STREAM_DETECTED', {
                        videoElementId: ensureVideoId(this),
                        isDRMProtected: true,
                        hasMediaKeys: true
                    });
                }
                return origSetKeys.apply(this, arguments);
            };
        }

        const origPlay = HTMLMediaElement.prototype.play;
        if (typeof origPlay === 'function') {
            HTMLMediaElement.prototype.play = function() {
                if (this.nodeName === 'VIDEO') {
                    inspectVideoElement(this);
                    postEvent('VIDEO_PLAYBACK_STATE', {
                        videoElementId: ensureVideoId(this),
                        currentTimeSeconds: Number.isFinite(this.currentTime) ? this.currentTime : 0,
                        playbackRate: Number.isFinite(this.playbackRate) ? this.playbackRate : 1.0,
                        wasPlaying: true,
                        isDRMProtected: isVideoDRM(this),
                        elementRectViewport: getViewportRect(this)
                    });
                }
                return origPlay.apply(this, arguments);
            };
        }
    }

    // 2. Fullscreen Interception Hooks (webkitEnterFullscreen, webkitSetPresentationMode, requestFullscreen)
    if (typeof HTMLVideoElement !== 'undefined' && HTMLVideoElement.prototype) {
        const origWebkitEnterFS = HTMLVideoElement.prototype.webkitEnterFullscreen;
        if (typeof origWebkitEnterFS === 'function') {
            HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
                if (attemptFullscreenIntercept(this)) return;
                return origWebkitEnterFS.apply(this, arguments);
            };
        }

        const origSetPresMode = HTMLVideoElement.prototype.webkitSetPresentationMode;
        if (typeof origSetPresMode === 'function') {
            HTMLVideoElement.prototype.webkitSetPresentationMode = function(mode) {
                if (mode === 'fullscreen' && attemptFullscreenIntercept(this)) return;
                return origSetPresMode.apply(this, arguments);
            };
        }
    }

    if (typeof Element !== 'undefined' && Element.prototype && typeof Element.prototype.requestFullscreen === 'function') {
        const origRequestFS = Element.prototype.requestFullscreen;
        Element.prototype.requestFullscreen = function() {
            const video = this.nodeName === 'VIDEO'
                ? this
                : (this.querySelector ? this.querySelector('video') : null);
            if (video && attemptFullscreenIntercept(video)) {
                return Promise.resolve();
            }
            return origRequestFS.apply(this, arguments);
        };
    }

    // 3. Network Hooks (fetch + XMLHttpRequest)
    if (typeof window.fetch === 'function') {
        const origFetch = window.fetch.bind(window);
        window.fetch = function(input, init) {
            const reqURL = typeof input === 'string' ? input : (input && input.url ? input.url : '');
            if (reqURL) recordNetworkCandidate(reqURL, null);
            return origFetch(input, init).then((response) => {
                try {
                    const finalURL = response.url || reqURL;
                    const ct = response.headers ? response.headers.get('content-type') : null;
                    recordNetworkCandidate(finalURL, ct);
                } catch (_) {}
                return response;
            });
        };
    }

    if (typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.prototype) {
        const origOpen = XMLHttpRequest.prototype.open;
        const origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__prismXhrUrl = typeof url === 'string' ? url : String(url || '');
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
            if (this.__prismXhrUrl) {
                recordNetworkCandidate(this.__prismXhrUrl, null);
            }
            this.addEventListener('readystatechange', function() {
                if (this.readyState === 2 || this.readyState === 4) {
                    try {
                        const ct = this.getResponseHeader('content-type');
                        recordNetworkCandidate(this.responseURL || this.__prismXhrUrl, ct);
                    } catch (_) {}
                }
            }, { passive: true });
            return origSend.apply(this, arguments);
        };
    }

    // 4. URL.createObjectURL hook for MediaSource / Blob tracking
    if (typeof URL !== 'undefined' && typeof URL.createObjectURL === 'function') {
        const origCreateObjectURL = URL.createObjectURL.bind(URL);
        URL.createObjectURL = function(obj) {
            const blobUrl = origCreateObjectURL(obj);
            if (typeof MediaSource !== 'undefined' && obj instanceof MediaSource) {
                pruneManifests();
                postEvent('BLOB_SOURCE_ATTACHED', {
                    blobUrl: blobUrl,
                    recentNetworkManifests: state.recentManifests.map((m) => m.url),
                    hasMediaKeys: state.frameHasEME,
                    isDRMProtected: state.frameHasEME
                });
            }
            return blobUrl;
        };
    }

    // 5. DOM MutationObserver for dynamic <video> & <source> elements
    function scanDocument() {
        try {
            document.querySelectorAll('video').forEach(inspectVideoElement);
        } catch (_) {}
    }

    if (typeof MutationObserver !== 'undefined') {
        const observer = new MutationObserver((mutations) => {
            for (const m of mutations) {
                for (const node of m.addedNodes) {
                    if (!node || node.nodeType !== 1) continue;
                    if (node.nodeName === 'VIDEO') {
                        inspectVideoElement(node);
                    } else if (node.nodeName === 'SOURCE' && node.parentElement && node.parentElement.nodeName === 'VIDEO') {
                        inspectVideoElement(node.parentElement);
                    } else if (node.querySelectorAll) {
                        node.querySelectorAll('video').forEach(inspectVideoElement);
                    }
                }
            }
        });
        const startObserving = () => {
            if (!document.documentElement) return;
            observer.observe(document.documentElement, { childList: true, subtree: true });
            scanDocument();
        };
        if (document.documentElement) {
            startObserving();
        } else {
            document.addEventListener('DOMContentLoaded', startObserving, { once: true });
        }
    }
})();
