// The event listener for fetch events
addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

// Main handler function for requests
async function handleRequest(request) {
    const USERNAME = self["shared_auth_user"];
    const PASSWORD = self["shared_auth_password"];
    const url = new URL(request.url);

    // If the request is for a .well-known route, don't protect or redirect it:
    // the origin answers ACME HTTP-01 challenges over plain http when it issues
    // or renews its certificate.
    // Match the path prefix only: a substring check on the full URL would let
    // any request bypass auth by placing ".well-known" in the query string.
    if (url.pathname.startsWith('/.well-known/')) {
        return secureResponse(url, await fetch(request), false);
    }

    // Send plain http to https before asking for credentials, so a browser
    // never sends them in clear.
    if (url.protocol === 'http:') {
        return redirectToHttps(request, url);
    }

    const authorization = request.headers.get('authorization');

    // Check if the authorization header is missing or doesn't start with 'Basic '
    if (!authorization || !authorization.startsWith('Basic ')) {
        return secureResponse(url, getUnauthorizedResponse(
            'Provide User Name and Password to access this page.'
        ), false);
    }

    // Parse the credentials from the Authorization header
    const credentials = parseCredentials(authorization);

    // Validate the credentials against the environment variables
    if (!credentials || credentials[0] !== USERNAME || credentials[1] !== PASSWORD) {
        return secureResponse(url, getUnauthorizedResponse(
            'The User Name and Password combination you have entered is invalid.'
        ), false);
    }

    return secureResponse(url, await fetch(request), true);
}

// Returns [user, password], or null when the header is not valid base64 or
// holds no ':' separator.
function parseCredentials(authorization) {
    const base64Credentials = authorization.split(' ')[1]; // Get base64 string after 'Basic '
    let plainAuth;
    try {
        plainAuth = atob(base64Credentials); // Decode base64 to plain text
    } catch {
        return null;
    }
    if (!plainAuth.includes(':')) {
        return null;
    }
    return plainAuth.split(':'); // Split into username and password
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

function getUnauthorizedResponse(message) {
    const response = new Response(message, {
        status: 401,
    });
    response.headers.set('WWW-Authenticate', 'Basic realm="Secure Area"');
    return response;
}
