addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
    const url = new URL(request.url);

    // If the request is for a .well-known route, don't redirect it or mark it
    // noindex: the origin answers ACME HTTP-01 challenges over plain http when
    // it issues or renews its certificate. Match the path prefix only.
    if (url.pathname.startsWith('/.well-known/')) {
        return secureResponse(url, await fetch(request), false);
    }

    // Send plain http to https.
    if (url.protocol === 'http:') {
        return redirectToHttps(request, url);
    }

    return secureResponse(url, await fetch(request), true);
}

// 301 for GET and HEAD; 308 for any other method, so the client repeats the
// method and its body against https.
function redirectToHttps(request, url) {
    url.protocol = 'https:';
    url.port = '';
    const status = request.method === 'GET' || request.method === 'HEAD' ? 301 : 308;
    return Response.redirect(url.toString(), status);
}

// Adds X-Robots-Tag when asked and, on https, HSTS unless the origin sent its
// own. fetch() responses have immutable headers, so the response is copied
// first. A protocol switch (status 101 or a WebSocket) is returned untouched.
function secureResponse(url, response, noindex) {
    if (response.status === 101 || response.webSocket) {
        return response;
    }

    const newResponse = new Response(response.body, response);
    if (noindex) {
        newResponse.headers.set('X-Robots-Tag', 'noindex, nofollow');
    }
    if (url.protocol === 'https:' && !newResponse.headers.has('Strict-Transport-Security')) {
        newResponse.headers.set('Strict-Transport-Security', 'max-age=31536000');
    }

    return newResponse;
}
