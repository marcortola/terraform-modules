addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
    const USERNAME = self["shared_auth_user"];
    const PASSWORD = self["shared_auth_password"];

    // If the request is for a .well-known route, don't protect it
    if (request.url.includes('.well-known')) {
        return await fetch(request);
    }

    const authorization = request.headers.get('authorization');

    // Check if the authorization header is missing or doesn't start with 'Basic '
    if (!authorization || !authorization.startsWith('Basic ')) {
        return getUnauthorizedResponse(
            'Provide User Name and Password to access this page.'
        );
    }

    // Parse the credentials from the Authorization header
    const credentials = parseCredentials(authorization);

    // Validate the credentials against the environment variables
    if (credentials[0] !== USERNAME || credentials[1] !== PASSWORD) {
        return getUnauthorizedResponse(
            'The User Name and Password combination you have entered is invalid.'
        );
    }

    // If authentication is successful, forward the request
    return await fetch(request);
}

function parseCredentials(authorization) {
    const base64Credentials = authorization.split(' ')[1]; // Get base64 string after 'Basic '
    const plainAuth = atob(base64Credentials); // Decode base64 to plain text
    const credentials = plainAuth.split(':'); // Split into username and password
    return credentials;
}

function getUnauthorizedResponse(message) {
    const response = new Response(message, {
        status: 401,
    });
    response.headers.set('WWW-Authenticate', 'Basic realm="Secure Area"');
    return response;
}