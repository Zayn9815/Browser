(() => {
    'use strict';
    window.__prismExtractReaderArticle = function() {
        try {
            if (typeof Readability === 'undefined') {
                return JSON.stringify({ error: 'Readability library not loaded.' });
            }
            const clonedDoc = document.cloneNode(true);
            const reader = new Readability(clonedDoc, {
                charThreshold: 180,
                keepClasses: false
            });
            const article = reader.parse();
            if (!article || !article.content) {
                return JSON.stringify({ error: 'No readable article detected on this page.' });
            }

            // Strip any residual <script>, <noscript>, or <iframe> elements before handing off HTML
            const container = document.createElement('div');
            container.innerHTML = article.content;
            container.querySelectorAll('script, iframe, object, embed, form').forEach((el) => el.remove());

            return JSON.stringify({
                title: article.title || document.title || 'Reader Article',
                byline: article.byline || '',
                siteName: article.siteName || location.hostname || '',
                excerpt: article.excerpt || '',
                contentHTML: container.innerHTML,
                textLength: (article.textContent || '').length
            });
        } catch (err) {
            return JSON.stringify({ error: String(err && err.message ? err.message : err) });
        }
    };
})();
