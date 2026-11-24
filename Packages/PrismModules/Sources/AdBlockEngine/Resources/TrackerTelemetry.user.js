(() => {
    'use strict';
    if (window.__prismTrackerTelemetryInstalled) return;
    window.__prismTrackerTelemetryInstalled = true;

    let blockedCount = 0;
    let flushTimer = null;

    function postDelta() {
        flushTimer = null;
        if (blockedCount <= 0) return;
        const delta = blockedCount;
        blockedCount = 0;
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.prismTrackerTelemetry) {
                window.webkit.messageHandlers.prismTrackerTelemetry.postMessage({
                    host: location.hostname || '',
                    delta: delta
                });
            }
        } catch (_) {}
    }

    function recordBlocked() {
        blockedCount += 1;
        if (!flushTimer) {
            flushTimer = setTimeout(postDelta, 250);
        }
    }

    // Observe PerformanceResourceTiming entries blocked by WebKit Content Blocker (0 transfer/encoded size & duration == 0)
    if (typeof PerformanceObserver !== 'undefined') {
        try {
            const observer = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                    if (entry.initiatorType && entry.transferSize === 0 && entry.encodedBodySize === 0 && entry.duration < 2) {
                        recordBlocked();
                    }
                }
            });
            observer.observe({ type: 'resource', buffered: true });
        } catch (_) {}
    }

    // Also capture script/img/iframe load errors triggered by WKContentRuleList block rules
    document.addEventListener('error', (event) => {
        const target = event.target;
        if (!target || !target.tagName) return;
        const tag = target.tagName.toUpperCase();
        if (tag === 'SCRIPT' || tag === 'IMG' || tag === 'IFRAME' || tag === 'LINK') {
            recordBlocked();
        }
    }, true);
})();
